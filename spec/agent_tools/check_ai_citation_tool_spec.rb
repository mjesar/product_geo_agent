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
  end
end
