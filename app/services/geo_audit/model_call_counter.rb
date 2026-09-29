module GeoAudit
  class ModelCallCounter
    STARTED_AT_KEY = :model_started_at

    def call(payload, context:)
      current_audit = CurrentAudit.current
      current_audit.tracker.record_call!(:agent)

      context.state[STARTED_AT_KEY] ||= {}
      context.state[STARTED_AT_KEY][payload[:turn].to_s] = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      current_audit.reporter.event(
        :agent_call_started, turn: payload[:turn], request: payload[:request].messages.map(&:to_h)
      )
      nil
    end
  end
end
