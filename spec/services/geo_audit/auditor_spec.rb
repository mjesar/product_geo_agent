require "rails_helper"

RSpec.describe GeoAudit::Auditor do
  let(:run_usage) { instance_double(LittleGhost::Usage, input_tokens: 120, output_tokens: 30) }

  def completed_run(state:, ratings:, usage: run_usage)
    instance_double(
      LittleGhost::Run,
      completed?: true,
      usage: usage,
      result: instance_double(
        LittleGhost::RunResult,
        state: state,
        structured_result: instance_double(LittleGhost::StructuredResult, value: ratings)
      )
    )
  end

  def failed_run(outcome:, error:, usage: run_usage)
    instance_double(LittleGhost::Run, completed?: false, outcome: outcome, error: error, usage: usage)
  end

  let(:tool_results) { { get_product_data: { title: "Cozy Wool Socks" } } }
  let(:ratings) { { description_quality: { rating: "good", reason: "Names material and fit." } } }
  let(:score_result) { GeoAudit::Score::Result.new(total: 82, items: []) }
  let(:clock_times) { [0.0, 4.5] }
  let(:clock) { -> { clock_times.shift } }

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

      result = described_class.new(clock: clock).call(handle: "cozy-wool-socks")

      expect(result.run).to eq(run)
      expect(result.score).to eq(score_result)
      expect(result.explanation).to eq("Add a FAQ page.")
      expect(result.elapsed_seconds).to eq(4.5)
    end

    it "records the run's own usage under the agent part of the usage snapshot" do
      stub_collaborators(run: completed_run(state: tool_results, ratings: ratings))

      result = described_class.new(clock: clock).call(handle: "cozy-wool-socks")

      # calls/retries are 0 here because GeoAuditAgent.ask is stubbed, so the real
      # before_model/ModelErrorRecovery hooks never run — only Auditor's own direct
      # read of run.usage is under test in this spec, not the full hook wiring
      # (that's covered live in geo_audit_agent_live_spec.rb).
      expect(result.usage.agent).to eq(
        GeoAudit::Usage::PartSnapshot.new(calls: 0, retries: 0, input_tokens: 120, output_tokens: 30)
      )
    end

    it "clears the current usage tracker after a successful call" do
      stub_collaborators(run: completed_run(state: tool_results, ratings: ratings))

      described_class.new.call(handle: "cozy-wool-socks")

      expect(GeoAudit::Usage.current_tracker).to be_nil
    end

    it "raises a clear error when the run did not complete" do
      run = failed_run(outcome: "failed", error: StandardError.new("Gemini rate limited"))
      allow(GeoAuditAgent).to receive(:ask).and_return(run)

      expect { described_class.new.call(handle: "cozy-wool-socks") }.to raise_error(
        "GeoAuditAgent run did not complete (failed): Gemini rate limited"
      )
    end

    it "clears the current usage tracker even when the run did not complete" do
      run = failed_run(outcome: "failed", error: StandardError.new("Gemini rate limited"))
      allow(GeoAuditAgent).to receive(:ask).and_return(run)

      expect { described_class.new.call(handle: "cozy-wool-socks") }.to raise_error(StandardError)
      expect(GeoAudit::Usage.current_tracker).to be_nil
    end
  end
end
