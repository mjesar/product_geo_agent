module GeoAudit
  class Auditor
    Result = Data.define(:run, :score, :explanation, :usage, :elapsed_seconds)

    def initialize(clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @clock = clock
    end

    def call(handle:)
      tracker = Usage::Tracker.new
      started_at = @clock.call
      Usage.current_tracker = tracker

      run = GeoAuditAgent.ask(
        "Audit the Shopify product with handle '#{handle}' for AI discoverability."
      )
      # run.usage is populated even when the run fails, unlike run.result (nil on failure) —
      # capturing it here keeps token totals accurate regardless of what happens next.
      tracker.record_tokens(:agent, run.usage)

      unless run.completed?
        raise "GeoAuditAgent run did not complete (#{run.outcome}): #{run.error&.message}"
      end

      score = Score.new(tool_results: run.result.state, ratings: run.result.structured_result.value).call
      explanation = GapsExplanation.new.call(score: score)

      Result.new(run:, score:, explanation:, usage: tracker.snapshot, elapsed_seconds: @clock.call - started_at)
    ensure
      Usage.current_tracker = nil
    end
  end
end
