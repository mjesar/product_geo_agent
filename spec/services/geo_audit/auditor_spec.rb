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
  let(:clock_times) { [ 0.0, 4.5 ] }
  let(:clock) { -> { clock_times.shift } }

  # Auditor's default lookup would hit the real Storefront API, so every example
  # gets a stand-in that says the product exists unless it overrides this.
  let(:product_lookup) { instance_double(GeoAudit::ProductLookup, exists?: true) }
  before { allow(GeoAudit::ProductLookup).to receive(:new).and_return(product_lookup) }

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

    it "sets the current audit before the run and clears it afterward" do
      current_audit_during_run = nil
      allow(GeoAuditAgent).to receive(:ask) do
        current_audit_during_run = GeoAudit::CurrentAudit.current
        completed_run(state: tool_results, ratings: ratings)
      end
      allow(GeoAudit::Score).to receive(:new).and_return(instance_double(GeoAudit::Score, call: score_result))
      allow(GeoAudit::GapsExplanation).to receive(:new).and_return(
        instance_double(GeoAudit::GapsExplanation, call: "Add a FAQ page.")
      )

      described_class.new.call(handle: "cozy-wool-socks")

      expect(current_audit_during_run).to be_a(GeoAudit::CurrentAudit)
      expect { GeoAudit::CurrentAudit.current }.to raise_error(GeoAudit::CurrentAudit::MissingError)
    end

    it "clears the current audit even when the run did not complete" do
      run = failed_run(outcome: "failed", error: StandardError.new("Gemini rate limited"))
      allow(GeoAuditAgent).to receive(:ask).and_return(run)

      expect { described_class.new.call(handle: "cozy-wool-socks") }.to raise_error(StandardError)
      expect { GeoAudit::CurrentAudit.current }.to raise_error(GeoAudit::CurrentAudit::MissingError)
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
      # (that's covered by the real-hook-path spec).
      expect(result.usage.agent).to eq(
        GeoAudit::Usage::PartSnapshot.new(calls: 0, retries: 0, input_tokens: 120, output_tokens: 30)
      )
    end

    it "announces the start, the computed score, and the final usage summary to the reporter" do
      reporter = instance_double(GeoAudit::Reporter::Null, event: nil)
      stub_collaborators(run: completed_run(state: tool_results, ratings: ratings), explanation: "Add a FAQ page.")

      described_class.new(clock: clock, reporter: reporter).call(handle: "cozy-wool-socks")

      expect(reporter).to have_received(:event).with(:start, handle: "cozy-wool-socks", model: GeoAuditAgent.model)
      expect(reporter).to have_received(:event).with(:score_computed, result: score_result)
      expect(reporter).to have_received(:event).with(:explanation, text: "Add a FAQ page.")
      expect(reporter).to have_received(:event).with(
        :usage_summary, snapshot: instance_of(GeoAudit::Usage::Snapshot), elapsed: 4.5
      )
    end

    context "when the handle does not resolve to a product" do
      let(:product_lookup) { instance_double(GeoAudit::ProductLookup, exists?: false) }

      it "raises ProductNotFound without ever calling the agent" do
        allow(GeoAuditAgent).to receive(:ask)

        expect { described_class.new.call(handle: "no-such-socks") }.to raise_error(
          GeoAudit::Auditor::ProductNotFound, "no product found for handle 'no-such-socks'"
        )
        expect(GeoAuditAgent).not_to have_received(:ask)
      end

      it "announces the failure to the reporter before raising" do
        reporter = instance_double(GeoAudit::Reporter::Null, event: nil)

        expect { described_class.new(reporter: reporter).call(handle: "no-such-socks") }.to raise_error(
          GeoAudit::Auditor::ProductNotFound
        )

        expect(reporter).to have_received(:event).with(
          :failure, step: "product lookup", reason: "no product found for handle 'no-such-socks'", partial_results: {}
        )
      end

      it "does not leave a current audit set" do
        expect { described_class.new.call(handle: "no-such-socks") }.to raise_error(StandardError)
        expect { GeoAudit::CurrentAudit.current }.to raise_error(GeoAudit::CurrentAudit::MissingError)
      end
    end

    it "checks the handle it was given" do
      stub_collaborators(run: completed_run(state: tool_results, ratings: ratings))

      described_class.new.call(handle: "cozy-wool-socks")

      expect(product_lookup).to have_received(:exists?).with("cozy-wool-socks")
    end

    it "raises a clear error when the run did not complete" do
      run = failed_run(outcome: "failed", error: StandardError.new("Gemini rate limited"))
      allow(GeoAuditAgent).to receive(:ask).and_return(run)

      expect { described_class.new.call(handle: "cozy-wool-socks") }.to raise_error(
        "GeoAuditAgent run did not complete (failed): Gemini rate limited"
      )
    end

    it "announces the failure to the reporter before raising" do
      reporter = instance_double(GeoAudit::Reporter::Null, event: nil)
      run = failed_run(outcome: "failed", error: StandardError.new("Gemini rate limited"))
      allow(GeoAuditAgent).to receive(:ask).and_return(run)

      expect { described_class.new(reporter: reporter).call(handle: "cozy-wool-socks") }.to raise_error(StandardError)

      expect(reporter).to have_received(:event).with(
        :failure, step: "agent run", reason: "Gemini rate limited", partial_results: {}
      )
    end

    it "includes any tool results collected before the run failed" do
      reporter = instance_double(GeoAudit::Reporter::Null, event: nil)
      run = failed_run(outcome: "failed", error: StandardError.new("Gemini rate limited"))
      allow(GeoAuditAgent).to receive(:ask) do
        GeoAudit::CurrentAudit.current.record_tool_result("get_product_data", { title: "Cozy Wool Socks" })
        run
      end

      expect { described_class.new(reporter: reporter).call(handle: "cozy-wool-socks") }.to raise_error(StandardError)

      expect(reporter).to have_received(:event).with(
        :failure, step: "agent run", reason: "Gemini rate limited",
        partial_results: { "get_product_data" => { title: "Cozy Wool Socks" } }
      )
    end
  end
end
