module GeoAudit
  module Usage
    PartSnapshot = Data.define(:calls, :retries, :input_tokens, :output_tokens)
    Snapshot = Data.define(:agent, :citation, :explanation, :total)

    # GeoAuditAgent's hooks (before_model, ModelErrorRecovery) and CitationCheck's
    # default retrier are all singletons/defaults evaluated outside Auditor's
    # control, so this thread-local is how the current audit's tracker reaches
    # them. Safe here since bin/audit runs exactly one audit per process at a time.
    def self.current_tracker
      Thread.current[:geo_audit_usage_tracker]
    end

    def self.current_tracker=(tracker)
      Thread.current[:geo_audit_usage_tracker] = tracker
    end

    class Tracker
      PARTS = %i[agent citation explanation].freeze

      def initialize
        @counts = PARTS.to_h { |part| [part, { calls: 0, retries: 0, input_tokens: 0, output_tokens: 0 }] }
      end

      # fetch, not [], so a typo'd part fails loudly instead of silently tracking nothing
      def record_call!(part)
        @counts.fetch(part)[:calls] += 1
      end

      def record_retry!(part)
        @counts.fetch(part)[:retries] += 1
      end

      def record_tokens(part, usage)
        @counts.fetch(part)[:input_tokens] += usage.input_tokens
        @counts.fetch(part)[:output_tokens] += usage.output_tokens
      end

      def snapshot
        parts = PARTS.to_h { |part| [part, PartSnapshot.new(**@counts.fetch(part))] }
        total = PartSnapshot.new(
          calls: parts.values.sum(&:calls),
          retries: parts.values.sum(&:retries),
          input_tokens: parts.values.sum(&:input_tokens),
          output_tokens: parts.values.sum(&:output_tokens)
        )
        Snapshot.new(**parts, total:)
      end
    end
  end
end
