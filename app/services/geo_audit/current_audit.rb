module GeoAudit
  class CurrentAudit
    class MissingError < StandardError; end

    MISSING_MESSAGE = "GeoAudit::CurrentAudit missing — was Auditor#call's " \
                       "CurrentAudit.current= assignment skipped, or already cleared?"

    attr_reader :tracker, :reporter, :tool_results

    def initialize(tracker:, reporter:)
      @tracker = tracker
      @reporter = reporter
      @tool_results = {}
    end

    def record_tool_result(name, value)
      @tool_results[name] = value
    end

    # Confirmed against a real run: little_ghost's Agent#stream hardcodes
    # RunContext#metadata to {agent_id: ...} — a metadata: option passed to
    # .ask never reaches context.metadata in any hook, and context.state is
    # JSON-only, so neither can carry a live object through. This Thread.current
    # slot is the one genuine global in this app; set by Auditor before the run
    # and cleared in an ensure, safe since bin/audit runs one audit at a time.
    def self.current
      Thread.current[:geo_audit_current_audit] || raise(MissingError, MISSING_MESSAGE)
    end

    def self.current=(value)
      Thread.current[:geo_audit_current_audit] = value
    end
  end
end
