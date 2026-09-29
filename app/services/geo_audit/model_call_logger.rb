module GeoAudit
  class ModelCallLogger
    def call(payload, context:)
      current_audit = CurrentAudit.current
      tool_names = tool_names_for(payload[:response])
      current_audit.reporter.event(
        :agent_call_finished,
        turn: payload[:turn],
        duration: duration_for(payload[:turn], context),
        decision: decision_for(tool_names),
        tool_names: tool_names,
        response: payload[:response].message.to_h
      )
      nil
    end

    private

    def duration_for(turn, context)
      started_at = context.state.dig(ModelCallCounter::STARTED_AT_KEY, turn.to_s)
      return nil unless started_at

      Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
    end

    def tool_names_for(response)
      response.message.content.grep(LittleGhost::Content::ToolUse).map(&:name)
    end

    def decision_for(tool_names)
      return "answered without a tool call" if tool_names.empty?

      "chose tool#{"s" if tool_names.size > 1} #{tool_names.join(', ')}"
    end
  end
end
