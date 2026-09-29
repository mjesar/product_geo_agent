module GeoAudit
  module Reporter
    class Terminal
      def initialize(
        io: $stdout,
        clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
        redactor: GeoAudit::Redactor.new
      )
        @io = io
        @clock = clock
        @redactor = redactor
        @started_at = nil
        @call_count = 0
      end

      # Every event's data passes through the redactor here, in this one place,
      # before any formatter below ever sees it — so no formatter has to
      # remember to redact on its own.
      def event(name, **data)
        redacted = @redactor.redact(data)
        case name
        when :start then start(**redacted)
        when :agent_call_started then agent_call_started(**redacted)
        when :agent_call_finished then agent_call_finished(**redacted)
        when :tool_finished then tool_finished(**redacted)
        when :retry then retry_attempt(**redacted)
        when :score_computed then score_computed(**redacted)
        when :failure then failure(**redacted)
        when :usage_summary then usage_summary(**redacted)
          # Unrecognized event names are ignored, not raised on — this reporter
          # is forward-compatible with event types added before it's updated.
        end
      end

      private

      def start(handle:, model:)
        @started_at = @clock.call
        @io.puts "Audit: #{handle}   (model: #{model})"
      end

      def agent_call_started(turn:)
        @call_count += 1
        line "Gemini call #{@call_count}: asking what to do next"
      end

      def agent_call_finished(turn:, duration:, decision:)
        line "  #{decision}  (#{format_seconds(duration)})"
      end

      def tool_finished(name:, duration:, summary:)
        line "Tool #{name}: #{summary}"
      end

      def retry_attempt(part:, attempt:, delay:, status:, reason:)
        line "!! #{part} busy (#{status}), retrying in #{delay}s (attempt #{attempt}): #{reason}"
      end

      def score_computed(result:)
        line "Ruby calculates the score: TOTAL #{result.total}/100"
      end

      def failure(step:, reason:)
        line "!! #{step} failed: #{reason}"
      end

      def usage_summary(snapshot:, elapsed:)
        total = snapshot.total
        @io.puts "Usage: #{total.calls} calls, #{total.input_tokens} tokens in, " \
                  "#{total.output_tokens} out, #{format_seconds(elapsed)}"
      end

      def line(text)
        @io.puts "[#{elapsed_label}] #{text}"
      end

      # mm:ss.s, distinct from format_seconds — this is a running clock label,
      # not a duration, so it always shows minutes even at zero.
      def elapsed_label
        minutes, remaining = (@clock.call - @started_at).divmod(60)
        format("%02d:%04.1f", minutes, remaining)
      end

      def format_seconds(seconds)
        return "?s" unless seconds

        "#{format('%.1f', seconds)}s"
      end
    end
  end
end
