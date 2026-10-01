module GeoAudit
  module Eval
    # Plain-text rendering of one ProductReport. No colour, so it reads the same in a
    # terminal, a pipe or a pasted PR comment.
    class ReportFormatter
      LABELS = { pass: "PASS", off_expectation: "OFF", flaky: "FLAKY", fail: "FAIL" }.freeze

      # drift is an optional Drift::Result. It is shown as its own section and never
      # changes the PASS/FAIL result.
      def initialize(report, drift: nil)
        @report = report
        @drift = drift
      end

      def call
        [ header, *score_line, "", *@report.items.map { |item| item_line(item) }, *error_lines,
          *drift_lines, "", result_line ].join("\n")
      end

      private

      def header
        errored = @report.errors.size
        "#{@report.handle}: #{@report.completed} completed run(s)#{", #{errored} errored" if errored.positive?}"
      end

      def score_line
        return [] if @report.scores.empty?

        sorted = @report.scores.sort
        [ "score  min #{sorted.first}  median #{format('%g', @report.median_score)}  max #{sorted.last}" ]
      end

      def item_line(item)
        format("%-5s %-7s %-26s expected %-40s observed %s",
               LABELS.fetch(item.verdict), item.kind, item.key, expected_text(item.expected), tally(item.observed))
      end

      def error_lines
        @report.errors.map { |message| "error: #{message}" }
      end

      def drift_lines
        return [] unless @drift

        meta = @drift.meta.values_at("model", "git_sha", "recorded_at").compact.join(", ")
        changes = @drift.changes.map { |change| "  #{change.key}: #{value_text(change.before)} -> #{value_text(change.after)}" }

        [ "", "drift vs baseline (#{meta}):", *(changes.presence || [ "  none" ]) ]
      end

      def result_line
        counts = @report.verdict_counts
        parts = LABELS.filter_map { |verdict, label| "#{counts[verdict]} #{label}" if counts[verdict] }
        verdict = @report.failed? ? "FAIL" : "PASS"

        "RESULT: #{verdict}#{" (#{parts.join(', ')})" if parts.any?}"
      end

      def tally(observed)
        observed.tally.sort_by { |value, count| [ -count, value.to_s ] }
                .map { |value, count| "#{value_text(value)} x#{count}" }.join(", ")
      end

      def expected_text(expected)
        case expected
        when Expectations::RatingExpectation
          # With a single accepted rating, "expect" would only repeat it.
          predicted = " (expect #{expected.expected})" if expected.expected && expected.accept.size > 1
          "#{expected.accept.join(' or ')}#{predicted}"
        else value_text(expected)
        end
      end

      def value_text(value)
        case value
        when nil then "not observed"
        when Numeric then format("%g", value)
        when Hash then "#{value[:with_alt]} of #{value[:of]} with alt"
        else value.to_s
        end
      end
    end
  end
end
