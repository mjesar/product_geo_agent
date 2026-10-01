module GeoAudit
  module Eval
    # A saved summary of one earlier eval run per product (spec/evals/baseline.json),
    # kept deliberately small: what each check observed and the score of each run, not
    # the raw tool output. It is what a new run is compared against to see drift, and it
    # is only ever replaced on purpose (bin/eval --save-baseline).
    class Baseline
      def initialize(path)
        @path = path
      end

      def entry_for(handle)
        read[handle]
      end

      def save(report, model:, git_sha:, at:)
        entry = {
          "recorded_at" => at, "model" => model, "git_sha" => git_sha,
          "scores" => report.scores,
          "items" => report.items.to_h { |item| [ "#{item.kind}:#{item.key}", item.observed.as_json ] }
        }

        File.write(@path, JSON.pretty_generate(read.merge(report.handle => entry)))
      end

      private

      def read
        File.exist?(@path) ? JSON.parse(File.read(@path)) : {}
      end
    end
  end
end
