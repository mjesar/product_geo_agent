module GeoAudit
  class Auditor
    Result = Data.define(:run, :score, :explanation)

    def call(handle:)
      run = GeoAuditAgent.ask(
        "Audit the Shopify product with handle '#{handle}' for AI discoverability."
      )
      unless run.completed?
        raise "GeoAuditAgent run did not complete (#{run.outcome}): #{run.error&.message}"
      end

      score = Score.new(tool_results: run.result.state, ratings: run.result.structured_result.value).call
      explanation = GapsExplanation.new.call(score: score)

      Result.new(run:, score:, explanation:)
    end
  end
end
