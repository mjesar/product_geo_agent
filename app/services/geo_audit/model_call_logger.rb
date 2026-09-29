module GeoAudit
  class ModelCallLogger
    def call(payload, context:)
      current_audit = CurrentAudit.current
      current_audit.reporter.event(
        :agent_call_finished,
        turn: payload[:turn],
        duration: duration_for(payload[:turn], context),
        decision: decision_for(payload[:response]),
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

    # The structured-result turn is itself a tool call (to the synthetic result
    # tool little_ghost generates from result_schema), so it falls under the
    # tool-use branch here too — no separate "final answer" case needed.
    def decision_for(response)
      tool_names = response.message.content.grep(LittleGhost::Content::ToolUse).map(&:name)
      return "answered without a tool call" if tool_names.empty?

      "chose tool#{"s" if tool_names.size > 1} #{tool_names.join(', ')}"
    end
  end
end
