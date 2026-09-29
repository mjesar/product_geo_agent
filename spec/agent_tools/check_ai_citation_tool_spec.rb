require "rails_helper"

RSpec.describe CheckAiCitationTool do
  let(:citation_check) { instance_double(GeoAudit::CitationCheck) }
  let(:tool) { described_class.new(citation_check: citation_check) }

  describe "#call" do
    it "delegates to CitationCheck with the product title and category, and returns its result" do
      allow(citation_check).to receive(:call)
        .with(product_title: "Cozy Wool Socks", category: "wool socks")
        .and_return(
          mentioned: true,
          question: "What's a good wool socks you'd recommend?",
          response: "I'd recommend Cozy Wool Socks."
        )

      result = tool.call({ "product_title" => "Cozy Wool Socks", "category" => "wool socks" })

      expect(result).to eq(
        mentioned: true,
        question: "What's a good wool socks you'd recommend?",
        response: "I'd recommend Cozy Wool Socks."
      )
    end

    it "builds a real CitationCheck wired to the current audit's tracker when none is injected" do
      tracker = GeoAudit::Usage::Tracker.new
      GeoAudit::CurrentAudit.current = GeoAudit::CurrentAudit.new(tracker: tracker, reporter: GeoAudit::Reporter::Null.new)
      response = instance_double(LittleGhost::RunResult, text: "Cozy Wool Socks are great.")
      allow(LittleGhost).to receive(:generate).and_return(response)

      result = described_class.new.call({ "product_title" => "Cozy Wool Socks", "category" => "wool socks" })

      expect(result[:mentioned]).to eq(true)
      expect(tracker.snapshot.citation.calls).to eq(1)
    ensure
      GeoAudit::CurrentAudit.current = nil
    end
  end
end
