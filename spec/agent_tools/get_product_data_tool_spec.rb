require "rails_helper"

RSpec.describe GetProductDataTool do
  let(:client) { instance_double(ShopifyStorefront::Client) }
  let(:tool) { described_class.new(client: client) }

  describe "#call" do
    context "when the product is found" do
      it "returns the product's title, description, images, variants, and seo" do
        allow(client).to receive(:query).and_return(
          "product" => {
            "title" => "Cozy Wool Socks",
            "description" => "Warm socks for winter.",
            "images" => {
              "edges" => [
                { "node" => { "altText" => "Socks on a table" } }
              ]
            },
            "variants" => {
              "edges" => [
                { "node" => { "title" => "Small", "price" => "12.00" } }
              ]
            },
            "seo" => { "title" => "Cozy Wool Socks", "description" => "Buy warm socks" }
          }
        )

        result = tool.call({ "handle" => "cozy-wool-socks" })

        expect(result).to eq(
          title: "Cozy Wool Socks",
          description: "Warm socks for winter.",
          images: [ "Socks on a table" ],
          variants: [ { title: "Small", price: "12.00" } ],
          seo: { "title" => "Cozy Wool Socks", "description" => "Buy warm socks" }
        )
      end
    end

    context "when the product is not found" do
      it "raises a ToolError" do
        allow(client).to receive(:query).and_return("product" => nil)

        expect { tool.call({ "handle" => "missing-handle" }) }
          .to raise_error(LittleGhost::ToolError, /missing-handle/)
      end
    end
  end
end
