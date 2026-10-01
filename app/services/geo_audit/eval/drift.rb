module GeoAudit
  module Eval
    # Compares a new run's report with a saved baseline entry and lists what changed.
    # It compares the typical result across runs, not single runs, so ordinary
    # run-to-run noise (one flipped rating out of five) is not reported as drift.
    # Informational only: a shift can be an improvement, so it never fails a product.
    class Drift
      RATING_RANK = Score::RATING_POINTS.keys.each_with_index.to_h.freeze

      # Five points is the smallest a judged rating can move the score (half of the
      # lightest judged item, specs_clarity at 10).
      SCORE_STEP = 5

      Change = Data.define(:key, :before, :after)
      Result = Data.define(:meta, :changes) do
        def drifted?
          changes.any?
        end
      end

      def call(entry, report)
        changes = report.items.filter_map { |item| item_change(entry, item) }
        changes << score_change(entry, report)

        Result.new(meta: entry.slice("model", "git_sha", "recorded_at"), changes: changes.compact)
      end

      private

      def item_change(entry, item)
        key = "#{item.kind}:#{item.key}"
        before = entry["items"][key]
        return if before.nil?

        was = typical(item.kind, before)
        now = typical(item.kind, item.observed.as_json)
        Change.new(key: key, before: was, after: now) unless was == now
      end

      def score_change(entry, report)
        before = median(entry["scores"])
        after = report.median_score
        return if before.nil? || after.nil? || (after - before).abs < SCORE_STEP

        Change.new(key: "score", before: before, after: after)
      end

      # A rating's typical value is its median by rank (poor < fair < good), so a
      # lone outlier among five runs does not move it. Facts and tool calls have no
      # order, so theirs is the most common value (ties broken the same way each time).
      def typical(kind, values)
        if kind == :rating
          values.sort_by { |value| RATING_RANK.fetch(value, -1) }[(values.size - 1) / 2]
        else
          values.tally.min_by { |value, count| [ -count, value.to_s ] }.first
        end
      end

      def median(scores)
        return nil if scores.blank?

        sorted = scores.sort
        (sorted[(sorted.size - 1) / 2] + sorted[sorted.size / 2]) / 2.0
      end
    end
  end
end
