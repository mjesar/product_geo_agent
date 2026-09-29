module GeoAudit
  class ToolTimer
    STARTED_AT_KEY = :tool_started_at

    def call(payload, context:)
      context.state[STARTED_AT_KEY] ||= {}
      context.state[STARTED_AT_KEY][payload[:tool_use].id] = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      nil
    end
  end
end
