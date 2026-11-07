module GeoAudit
  class Auditor
    Result = Data.define(:run, :score, :explanation, :usage, :elapsed_seconds)

    class ProductNotFound < StandardError; end
    class IncompleteAudit < StandardError; end

    def initialize(clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }, reporter: Reporter::Null.new,
                   product_lookup: ProductLookup.new, explain: true)
      @clock = clock
      @reporter = reporter
      @product_lookup = product_lookup
      # The eval harness only needs the ratings and tool results, so it can skip the
      # gaps explanation, one fewer Gemini request per audit. Result#explanation is nil then.
      @explain = explain
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

      ensure_checks_succeeded!(current_audit)

      score = Score.new(tool_results: run.result.state, ratings: run.result.structured_result.value).call
      @reporter.event(:score_computed, result: score)

      explanation = nil
      if @explain
        explanation = GapsExplanation.new(retrier: Retrier.new(tracker: tracker, part: :explanation)).call(score: score)
        @reporter.event(:explanation, text: explanation)
      end

      usage = tracker.snapshot
      elapsed_seconds = @clock.call - started_at
      @reporter.event(:usage_summary, snapshot: usage, elapsed: elapsed_seconds)

      Result.new(run:, score:, explanation:, usage:, elapsed_seconds:)
    ensure
      CurrentAudit.current = nil
    end

    private

    # The model can finish its ratings even after a tool failed, but Score reads a
    # missing result as "not found". A check that never ran must not cost points,
    # so stop here with the real reason instead of printing a wrong number.
    def ensure_checks_succeeded!(current_audit)
      return if current_audit.tool_failures.empty?

      reason = current_audit.tool_failures.map { |name, message| "#{name}: #{message}" }.join("; ")
      @reporter.event(:failure, step: "tool check", reason: reason, partial_results: current_audit.tool_results)
      raise IncompleteAudit, "audit incomplete, no score given (#{reason})"
    end

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
