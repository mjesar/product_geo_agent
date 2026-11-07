module GeoAudit
  class ToolResultCollector
    def initialize(summarizer: ToolSummary.new)
      @summarizer = summarizer
    end

    def call(payload, context:)
      tool_use = payload[:tool_use]
      result = payload[:result]

      # A failed tool's value is its error message, a plain string, so it can't
      # go through the summarizer or into the state Score reads.
      if result.status == :success
        record_success(tool_use, result.value, context)
      else
        record_failure(tool_use, result.value.to_s, context)
      end

      nil
    end

    private

    def record_success(tool_use, value, context)
      # Still written to context.state too: Score reads run.result.state on the
      # success path, and that's unaffected by anything CurrentAudit does.
      context.state[tool_use.name] = value

      current_audit = CurrentAudit.current
      current_audit.record_tool_result(tool_use.name, value)
      current_audit.reporter.event(
        :tool_finished,
        name: tool_use.name,
        duration: duration_for(tool_use, context),
        summary: @summarizer.call(tool_use.name, value),
        input: tool_use.input,
        result: value
      )
    end

    def record_failure(tool_use, reason, context)
      current_audit = CurrentAudit.current
      current_audit.record_tool_failure(tool_use.name, reason)
      current_audit.reporter.event(
        :tool_failed,
        name: tool_use.name,
        duration: duration_for(tool_use, context),
        reason: reason,
        input: tool_use.input
      )
    end

    def duration_for(tool_use, context)
      started_at = context.state.dig(ToolTimer::STARTED_AT_KEY, tool_use.id)
      return nil unless started_at

      Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
    end
  end
end
