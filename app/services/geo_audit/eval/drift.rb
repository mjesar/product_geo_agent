module GeoAudit
  module Eval
    # Compares a new run's report with a saved baseline entry and lists what changed.
    # It compares the typical result across runs, not single runs, so ordinary
    # run-to-run noise (one flipped rating out of five) is not reported as drift.
    # Informational only: a shift can be an improvement, so it never fails a product.
    #
    # An item (or the score) whose runs split too evenly has no meaningful typical value:
    # a 3 to 2 split can come out the other way next batch, which would read as drift
    # when it is only noise. Those are listed as unstable and not compared.
    class Drift
      RATING_RANK = Score::RATING_POINTS.keys.each_with_index.to_h.freeze

      # Five points is the smallest a judged rating can move the score (half of the
      # lightest judged item, specs_clarity at 10).
      SCORE_STEP = 5

      # The most common value must account for at least this share of the runs, so 4 of
      # 5 is stable and 3 of 5 is not.
      STABLE_SHARE = 0.75

      Change = Data.define(:key, :before, :after)
      Unstable = Data.define(:key)
      Result = Data.define(:meta, :changes, :unstable) do
        def drifted?
          changes.any?
        end
      end

      def call(entry, report)
        outcomes = (report.items.map { |item| compare_item(entry, item) } + [ compare_scores(entry, report) ]).compact

        Result.new(meta: entry.slice("model", "git_sha", "recorded_at"),
                   changes: outcomes.grep(Change), unstable: outcomes.grep(Unstable).map(&:key))
      end

      private

      def compare_item(entry, item)
        key = "#{item.kind}:#{item.key}"
        before = entry["items"][key]
        return if before.nil?

        now = item.observed.as_json
        return Unstable.new(key: key) unless stable?(before) && stable?(now)

        was = typical(item.kind, before)
        is = typical(item.kind, now)
        Change.new(key: key, before: was, after: is) unless was == is
      end

      def compare_scores(entry, report)
        before = entry["scores"]
        now = report.scores
        return if before.blank? || now.blank?
        return Unstable.new(key: "score") unless stable?(before) && stable?(now)

        was = median(before)
        is = median(now)
        Change.new(key: "score", before: was, after: is) if (is - was).abs >= SCORE_STEP
      end

      def stable?(values)
        values.tally.values.max.to_f / values.size >= STABLE_SHARE
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
        sorted = scores.sort
        (sorted[(sorted.size - 1) / 2] + sorted[sorted.size / 2]) / 2.0
      end
    end
  end
end
