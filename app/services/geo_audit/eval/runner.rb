module GeoAudit
  module Eval
    # Runs the real agent against one product several times and collects what each run
    # produced. One run cannot see the model's variance (specs_clarity flipped fair/good
    # on an unchanged product), so the spread across runs is the actual measurement.
    # Judging the runs against expectations is Comparator's job, not this class's.
    class Runner
      # error is nil for a run that completed. A failed run is kept rather than raised,
      # so one rate-limited audit does not throw away the other four.
      Run = Data.define(:index, :ratings, :tool_results, :score, :calls, :error)

      # One audit makes roughly 7 requests (see CLAUDE.md). Used to pace a run that
      # failed before its real usage was known.
      ASSUMED_CALLS_ON_ERROR = 8

      def initialize(auditor: Auditor.new(explain: false), runs: 5, requests_per_minute: 15,
                     clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
                     sleeper: ->(seconds) { sleep(seconds) }, on_run: ->(_run) { })
        @auditor = auditor
        @runs = runs
        @seconds_per_request = 60.0 / requests_per_minute
        @clock = clock
        @sleeper = sleeper
        @on_run = on_run
      end

      def call(handle:)
        (1..@runs).map do |index|
          started_at = @clock.call
          run = audit(handle, index)
          @on_run.call(run)
          pace(run.calls, since: started_at) unless index == @runs
          run
        end
      end

      private

      def audit(handle, index)
        result = @auditor.call(handle: handle)

        Run.new(
          index: index,
          ratings: result.run.result.structured_result.value,
          tool_results: result.run.result.state,
          score: result.score,
          calls: result.usage.total.calls,
          error: nil
        )
      # A missing product would fail every run the same way, so stop instead of
      # reporting five identical errors.
      rescue Auditor::ProductNotFound
        raise
      rescue => error
        Run.new(index: index, ratings: nil, tool_results: nil, score: nil,
                calls: ASSUMED_CALLS_ON_ERROR, error: error.message)
      end

      # Keeps the average request rate under the limit: an audit that used n requests
      # must have taken at least n requests' worth of time before the next one starts.
      # Audits are slow enough that this often waits not at all.
      def pace(calls, since:)
        wait = (calls * @seconds_per_request) - (@clock.call - since)
        @sleeper.call(wait) if wait.positive?
      end
    end
  end
end
