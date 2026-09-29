module GeoAudit
  class ToolResultCollector
    def initialize(summarizer: ToolSummary.new)
      @summarizer = summarizer
    end

    def call(payload, context:)
      tool_use = payload[:tool_use]
      value = payload[:result].value

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

      nil
    end

    private

    def duration_for(tool_use, context)
      started_at = context.state.dig(ToolTimer::STARTED_AT_KEY, tool_use.id)
      return nil unless started_at

      Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
    end
  end
end
