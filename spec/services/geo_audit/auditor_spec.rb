require "rails_helper"

RSpec.describe GeoAudit::Auditor do
  def completed_run(state:, ratings:)
    instance_double(
      LittleGhost::Run,
      completed?: true,
      result: instance_double(
        LittleGhost::RunResult,
        state: state,
        structured_result: instance_double(LittleGhost::StructuredResult, value: ratings)
      )
    )
  end

  def failed_run(outcome:, error:)
    instance_double(LittleGhost::Run, completed?: false, outcome: outcome, error: error)
  end

  let(:tool_results) { { get_product_data: { title: "Cozy Wool Socks" } } }
  let(:ratings) { { description_quality: { rating: "good", reason: "Names material and fit." } } }
  let(:score_result) { GeoAudit::Score::Result.new(total: 82, items: []) }

  def stub_collaborators(run:, explanation: "Add a FAQ page.")
    allow(GeoAuditAgent).to receive(:ask).and_return(run)
    allow(GeoAudit::Score).to receive(:new).and_return(instance_double(GeoAudit::Score, call: score_result))
    allow(GeoAudit::GapsExplanation).to receive(:new).and_return(
      instance_double(GeoAudit::GapsExplanation, call: explanation)
    )
  end

  describe "#call" do
    it "asks GeoAuditAgent to audit the given handle" do
      stub_collaborators(run: completed_run(state: tool_results, ratings: ratings))

      described_class.new.call(handle: "cozy-wool-socks")

      expect(GeoAuditAgent).to have_received(:ask).with(
        "Audit the Shopify product with handle 'cozy-wool-socks' for AI discoverability."
      )
    end

    it "scores the run's tool results and ratings" do
      stub_collaborators(run: completed_run(state: tool_results, ratings: ratings))

      described_class.new.call(handle: "cozy-wool-socks")

      expect(GeoAudit::Score).to have_received(:new).with(tool_results: tool_results, ratings: ratings)
    end

    it "explains the score it just calculated" do
      gaps_explanation = instance_double(GeoAudit::GapsExplanation, call: "Add a FAQ page.")
      allow(GeoAuditAgent).to receive(:ask).and_return(completed_run(state: tool_results, ratings: ratings))
      allow(GeoAudit::Score).to receive(:new).and_return(instance_double(GeoAudit::Score, call: score_result))
      allow(GeoAudit::GapsExplanation).to receive(:new).and_return(gaps_explanation)

      described_class.new.call(handle: "cozy-wool-socks")

      expect(gaps_explanation).to have_received(:call).with(score: score_result)
    end

    it "returns the run, score, and explanation together" do
      run = completed_run(state: tool_results, ratings: ratings)
      stub_collaborators(run: run, explanation: "Add a FAQ page.")

      result = described_class.new.call(handle: "cozy-wool-socks")

      expect(result).to eq(
        GeoAudit::Auditor::Result.new(run: run, score: score_result, explanation: "Add a FAQ page.")
      )
    end

    it "raises a clear error when the run did not complete" do
      run = failed_run(outcome: "failed", error: StandardError.new("Gemini rate limited"))
      allow(GeoAuditAgent).to receive(:ask).and_return(run)

      expect { described_class.new.call(handle: "cozy-wool-socks") }.to raise_error(
        "GeoAuditAgent run did not complete (failed): Gemini rate limited"
      )
    end
  end
end
