module GeoAudit
  module Reporter
    class Terminal
      WIDTH = 60
      RESET = "\e[0m"
      BOLD = "\e[1m"
      DIM = "\e[2m"
      GREEN = "\e[32m"
      YELLOW = "\e[33m"
      RED = "\e[31m"
      CYAN = "\e[36m"

      def initialize(
        io: $stdout,
        redactor: GeoAudit::Redactor.new,
        summarizer: GeoAudit::ToolSummary.new,
        verbose: false,
        color: nil
      )
        @io = io
        @redactor = redactor
        @summarizer = summarizer
        @verbose = verbose
        @color = color.nil? ? (io.respond_to?(:tty?) && io.tty?) : color
      end

      # Every event's data passes through the redactor here, in this one place,
      # before any formatter below ever sees it — so no formatter has to
      # remember to redact on its own.
      def event(name, **data)
        redacted = @redactor.redact(data)
        case name
        when :start then start(**redacted)
        when :agent_call_finished then agent_call_finished(**redacted)
        when :tool_finished then tool_finished(**redacted)
        when :retry then retry_attempt(**redacted)
        when :score_computed then score_computed(**redacted)
        when :explanation then explanation(**redacted)
        when :failure then failure(**redacted)
        when :usage_summary then usage_summary(**redacted)
          # Unrecognized event names are ignored, not raised on — this reporter
          # is forward-compatible with event types added before it's updated.
        end
      end

      private

      def start(handle:, model:)
        box_open
        @io.puts "  #{paint(BOLD, "Auditing: #{handle}")}"
        @io.puts "  #{paint(DIM, "Model: #{model}")}"
        box_close
      end

      def agent_call_finished(turn:, duration:, decision:, tool_names: [], response: nil)
        @io.puts "#{paint(DIM, "→ Thinking...")}#{pad_duration(duration)}"
        @io.puts "  #{paint(GREEN, "✓")} Reasoning complete" if tool_names.empty?
      end

      def tool_finished(name:, duration:, summary:, input: nil, result: nil)
        @io.puts "  #{paint(GREEN, "✓")} #{paint(BOLD, name)} → #{summary}"
        return unless @verbose

        @io.puts "    #{paint(DIM, "input: #{input.inspect}")}"
        @io.puts "    #{paint(DIM, "result: #{result.inspect}")}"
      end

      def retry_attempt(part:, attempt:, delay:, status:, reason:)
        @io.puts "  #{paint(YELLOW, "⚠")} #{part} busy (#{status}) — retrying in #{delay}s (attempt #{attempt}): #{reason}"
      end

      def score_computed(result:)
        box_open
        @io.puts "  #{paint(BOLD + score_color(result.total), "Score: #{result.total} / 100")}"
      end

      def explanation(text:)
        @io.puts
        @io.puts "  #{paint(DIM, "Why:")} #{word_wrap(text)}"
      end

      def failure(step:, reason:, partial_results: {})
        @io.puts "  #{paint(RED, "✗")} #{step} failed: #{reason}"
        return if partial_results.empty?

        @io.puts "    #{paint(DIM, "Partial results before the failure:")}"
        partial_results.each do |name, value|
          @io.puts "      #{name} → #{@summarizer.call(name, value)}"
        end
      end

      def usage_summary(snapshot:, elapsed:)
        total = snapshot.total
        box_close
        @io.puts paint(
          DIM,
          "  #{total.calls} Gemini calls · #{total.input_tokens} in / #{total.output_tokens} out tokens · " \
          "#{format_seconds(elapsed)} total"
        )
      end

      def box_open = @io.puts paint(CYAN, "━" * WIDTH)
      def box_close = @io.puts paint(CYAN, "━" * WIDTH)

      def pad_duration(seconds)
        return "" unless seconds

        label = "(#{format_seconds(seconds)})"
        padding = [ WIDTH - 14 - label.length, 1 ].max
        "#{" " * padding}#{paint(DIM, label)}"
      end

      def word_wrap(text, width: WIDTH - 2)
        text.split.each_with_object([ +"" ]) do |word, lines|
          candidate = lines.last.empty? ? word : "#{lines.last} #{word}"
          candidate.length > width ? lines << +word : lines[-1] = candidate
        end.join("\n  ")
      end

      def score_color(total)
        return GREEN if total >= 70
        return YELLOW if total >= 40

        RED
      end

      def paint(code, text)
        @color ? "#{code}#{text}#{RESET}" : text
      end

      def format_seconds(seconds)
        return "?s" unless seconds

        "#{format('%.1f', seconds)}s"
      end
    end
  end
end
