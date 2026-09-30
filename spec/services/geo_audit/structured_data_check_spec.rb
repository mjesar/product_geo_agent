require "rails_helper"

RSpec.describe GeoAudit::StructuredDataCheck do
  let(:connection) { instance_double(Faraday::Connection) }
  let(:password_auth) { instance_double(ShopifyStorefront::PasswordAuth, authenticated_connection: connection) }
  let(:check) { described_class.new(password_auth: password_auth) }

  def stub_page(html)
    allow(connection).to receive(:get)
      .with("products/some-handle")
      .and_return(instance_double(Faraday::Response, body: html))
  end

  def page_with(*json_blocks)
    scripts = json_blocks.map { |json| %(<script type="application/ld+json">#{json}</script>) }
    "<html><head>#{scripts.join}</head></html>"
  end

  let(:complete_product) do
    { "@type" => "Product", "name" => "Socks", "description" => "Warm wool socks.",
      "offers" => [ { "@type" => "Offer", "price" => 12 } ] }.to_json
  end

  describe "#call" do
    context "when the page has a Product block with a description and offers" do
      it "reports the Product schema as present and complete" do
        stub_page(page_with(complete_product))

        result = check.call("some-handle")

        expect(result).to eq(
          product_schema: true, product_schema_complete: true, faq_schema: false, schema_types_found: [ "Product" ]
        )
      end
    end

    context "when the Product block has an empty description" do
      it "reports it as present but not complete" do
        stub_page(page_with(
          { "@type" => "Product", "name" => "Socks", "description" => "", "offers" => [ { "price" => 12 } ] }.to_json
        ))

        result = check.call("some-handle")

        expect(result).to include(product_schema: true, product_schema_complete: false)
      end
    end

    context "when the Product block has no offers" do
      it "reports it as present but not complete" do
        stub_page(page_with({ "@type" => "Product", "name" => "Socks", "description" => "Warm." }.to_json))

        result = check.call("some-handle")

        expect(result).to include(product_schema: true, product_schema_complete: false)
      end
    end

    context "when the page has FAQPage structured data" do
      it "reports faq_schema as true" do
        stub_page(page_with('{"@context":"https://schema.org","@type":"FAQPage","mainEntity":[]}'))

        result = check.call("some-handle")

        expect(result).to eq(
          product_schema: false, product_schema_complete: false, faq_schema: true, schema_types_found: [ "FAQPage" ]
        )
      end
    end

    context "when the page has no structured data" do
      it "reports everything as false" do
        stub_page("<html><head></head><body>No JSON-LD here</body></html>")

        result = check.call("some-handle")

        expect(result).to eq(
          product_schema: false, product_schema_complete: false, faq_schema: false, schema_types_found: []
        )
      end
    end

    context "when a script block contains invalid JSON" do
      it "skips it instead of raising" do
        stub_page(page_with("{not valid json}", complete_product))

        result = check.call("some-handle")

        expect(result).to include(product_schema: true, product_schema_complete: true)
      end
    end

    context "when the JSON-LD is a top-level array" do
      it "finds the entities inside it instead of raising" do
        stub_page(page_with("[#{complete_product}, {\"@type\":\"FAQPage\"}]"))

        result = check.call("some-handle")

        expect(result).to include(
          product_schema: true, product_schema_complete: true, faq_schema: true,
          schema_types_found: [ "Product", "FAQPage" ]
        )
      end
    end

    context "when the entities are wrapped in an @graph" do
      it "finds the entities inside the graph" do
        stub_page(page_with(%({"@context":"https://schema.org","@graph":[{"@type":"Organization"},#{complete_product}]})))

        result = check.call("some-handle")

        expect(result).to include(product_schema: true, product_schema_complete: true)
        expect(result[:schema_types_found]).to eq([ "Organization", "Product" ])
      end
    end
  end
end
