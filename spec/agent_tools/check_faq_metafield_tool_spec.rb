require "rails_helper"

RSpec.describe CheckFaqMetafieldTool do
  let(:faq_check) { instance_double(GeoAudit::FaqCheck) }
  let(:tool) { described_class.new(faq_check: faq_check) }

  describe "#call" do
    context "when the product's faq metafield exists" do
      it "delegates to FaqCheck#metafield with the handle and returns its result" do
        allow(faq_check).to receive(:metafield).with("cozy-wool-socks").and_return(
          found: true, value: "Q: Ships fast? A: Yes."
        )

        result = tool.call({ "handle" => "cozy-wool-socks" })

        expect(result).to eq(found: true, value: "Q: Ships fast? A: Yes.")
      end
    end

    context "when the product has no faq metafield" do
      it "returns found false with a nil value" do
        allow(faq_check).to receive(:metafield).and_return(found: false, value: nil)

        result = tool.call({ "handle" => "cozy-wool-socks" })

        expect(result).to eq(found: false, value: nil)
      end
    end

    context "independence from CheckFaqPageTool" do
      it "never calls FaqCheck#page — nothing in the tool enforces check_faq_page running first" do
        allow(faq_check).to receive(:metafield).and_return(found: true, value: "some answer")
        allow(faq_check).to receive(:page)

        tool.call({ "handle" => "cozy-wool-socks" })

        expect(faq_check).not_to have_received(:page)
      end
    end
  end
end
