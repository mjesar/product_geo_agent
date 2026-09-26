require "rails_helper"

RSpec.describe GeoAudit::FaqCheck do
  let(:client) { instance_double(ShopifyStorefront::Client) }
  let(:check) { described_class.new(client: client) }

  describe "#page" do
    context "when a faq page exists" do
      it "returns found true with the page's title and body" do
        allow(client).to receive(:query).and_return(
          "page" => { "title" => "Frequently Asked Questions", "body" => "<p>Answers here.</p>" }
        )

        result = check.page

        expect(result).to eq(found: true, title: "Frequently Asked Questions", body: "<p>Answers here.</p>")
      end
    end

    context "when no faq page exists" do
      it "returns found false with nil title and body" do
        allow(client).to receive(:query).and_return("page" => nil)

        result = check.page

        expect(result).to eq(found: false, title: nil, body: nil)
      end
    end
  end

  describe "#metafield" do
    context "when the product's faq metafield exists" do
      it "returns found true with the metafield's value" do
        allow(client).to receive(:query).and_return(
          "product" => { "metafield" => { "value" => "Q: Ships fast? A: Yes." } }
        )

        result = check.metafield("cozy-wool-socks")

        expect(result).to eq(found: true, value: "Q: Ships fast? A: Yes.")
      end

      it "passes the product handle through as a query variable" do
        allow(client).to receive(:query).and_return("product" => { "metafield" => nil })

        check.metafield("cozy-wool-socks")

        expect(client).to have_received(:query).with(anything, variables: { handle: "cozy-wool-socks" })
      end
    end

    context "when the product has no faq metafield" do
      it "returns found false with a nil value" do
        allow(client).to receive(:query).and_return("product" => { "metafield" => nil })

        result = check.metafield("cozy-wool-socks")

        expect(result).to eq(found: false, value: nil)
      end
    end
  end
end
