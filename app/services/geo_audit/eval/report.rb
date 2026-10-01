module GeoAudit
  module Eval
    # Turns the runs for one product into a verdict per check. One run is a sample, so
    # a check is judged on all of them: a rating that lands in the accepted set every
    # time is not the same as one that flips between two accepted values.
    class Report
      # observed and statuses hold one entry per completed run, in run order.
      # verdict: :fail (any run failed), :flaky (never failed, but the observed value
      # changed between runs), :off_expectation (stable, but not the predicted value)
      # or :pass.
      ItemSummary = Data.define(:kind, :key, :expected, :observed, :statuses, :verdict)

      ProductReport = Data.define(:handle, :completed, :errors, :items, :scores) do
        def failed?
          completed.zero? || items.any? { |item| item.verdict == :fail }
        end

        def verdict_counts
          items.map(&:verdict).tally
        end

        def median_score
          return nil if scores.empty?

          sorted = scores.sort
          (sorted[(sorted.size - 1) / 2] + sorted[sorted.size / 2]) / 2.0
        end
      end

      def initialize(expectation)
        @expectation = expectation
        @comparator = Comparator.new(expectation)
      end

      def call(runs)
        completed, errored = runs.partition { |run| run.error.nil? }
        results = completed.map { |run| @comparator.call(ratings: run.ratings, tool_results: run.tool_results) }

        ProductReport.new(
          handle: @expectation.handle,
          completed: completed.size,
          errors: errored.map(&:error),
          items: summarize(results),
          scores: completed.map { |run| run.score.total }
        )
      end

      private

      # group_by keeps first-seen order, so items come out as ratings, facts, tools.
      def summarize(results)
        results.flat_map(&:checks).group_by { |check| [ check.kind, check.key ] }.map do |(kind, key), checks|
          statuses = checks.map(&:status)
          observed = checks.map(&:observed)

          ItemSummary.new(kind: kind, key: key, expected: checks.first.expected, observed: observed,
                          statuses: statuses, verdict: verdict(statuses, observed))
        end
      end

      def verdict(statuses, observed)
        if statuses.include?(:fail) then :fail
        elsif observed.uniq.size > 1 then :flaky
        elsif statuses.include?(:off_expectation) then :off_expectation
        else :pass
        end
      end
    end
  end
end
