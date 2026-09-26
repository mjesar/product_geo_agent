require "rails_helper"

RSpec.describe GeoAudit::CitationCheck do
  let(:citation_check) { described_class.new }

  def stub_gemini_response(text)
    response = instance_double(LittleGhost::RunResult, text: text)
    allow(LittleGhost).to receive(:generate).and_return(response)
    response
  end

  describe "#call" do
    context "when the product is mentioned in the response" do
      it "returns mentioned true along with the question and full response" do
        stub_gemini_response("I'd recommend Cozy Wool Socks for winter.")

        result = citation_check.call(product_title: "Cozy Wool Socks", category: "wool socks")

        expect(result).to eq(
          mentioned: true,
          question: "What's a good wool socks you'd recommend?",
          response: "I'd recommend Cozy Wool Socks for winter."
        )
      end

      it "matches the product title case-insensitively" do
        stub_gemini_response("cozy wool socks are a great pick.")

        result = citation_check.call(product_title: "Cozy Wool Socks", category: "wool socks")

        expect(result[:mentioned]).to eq(true)
      end
    end

    context "when the product is not mentioned in the response" do
      it "returns mentioned false" do
        stub_gemini_response("There are many good options depending on your needs.")

        result = citation_check.call(product_title: "Cozy Wool Socks", category: "wool socks")

        expect(result[:mentioned]).to eq(false)
      end
    end

    it "asks a category-only question, without naming the product" do
      stub_gemini_response("Some answer.")

      citation_check.call(product_title: "Cozy Wool Socks", category: "wool socks")

      expect(LittleGhost).to have_received(:generate).with(
        model: GeoAudit::CitationCheck::MODEL,
        messages: [ { role: :user, content: "What's a good wool socks you'd recommend?" } ]
      )
    end
  end
end
