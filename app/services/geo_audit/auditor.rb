module GeoAudit
  class Auditor
    Result = Data.define(:run, :score, :explanation, :usage, :elapsed_seconds)

    class ProductNotFound < StandardError; end

    def initialize(clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }, reporter: Reporter::Null.new,
                   product_lookup: ProductLookup.new)
      @clock = clock
      @reporter = reporter
      @product_lookup = product_lookup
    end

    def call(handle:)
      tracker = Usage::Tracker.new
      current_audit = CurrentAudit.new(tracker: tracker, reporter: @reporter)
      started_at = @clock.call

      @reporter.event(:start, handle: handle, model: GeoAuditAgent.model)
      ensure_product_exists!(handle)
      CurrentAudit.current = current_audit

      run = GeoAuditAgent.ask("Audit the Shopify product with handle '#{handle}' for AI discoverability.")
      # run.usage is populated even when the run fails, unlike run.result (nil on failure) —
      # capturing it here keeps token totals accurate regardless of what happens next.
      tracker.record_tokens(:agent, run.usage)

      unless run.completed?
        reason = run.error&.message
        @reporter.event(:failure, step: "agent run", reason: reason, partial_results: current_audit.tool_results)
        raise "GeoAuditAgent run did not complete (#{run.outcome}): #{reason}"
      end

      score = Score.new(tool_results: run.result.state, ratings: run.result.structured_result.value).call
      @reporter.event(:score_computed, result: score)

      explanation = GapsExplanation.new(retrier: Retrier.new(tracker: tracker, part: :explanation)).call(score: score)
      @reporter.event(:explanation, text: explanation)

      usage = tracker.snapshot
      elapsed_seconds = @clock.call - started_at
      @reporter.event(:usage_summary, snapshot: usage, elapsed: elapsed_seconds)

      Result.new(run:, score:, explanation:, usage:, elapsed_seconds:)
    ensure
      CurrentAudit.current = nil
    end

    private

    # Checked in plain Ruby before the agent exists, so a typo'd handle costs one
    # Storefront request instead of several Gemini calls spent auditing nothing.
    def ensure_product_exists!(handle)
      return if @product_lookup.exists?(handle)

      reason = "no product found for handle '#{handle}'"
      @reporter.event(:failure, step: "product lookup", reason: reason, partial_results: {})
      raise ProductNotFound, reason
    end
  end
end
