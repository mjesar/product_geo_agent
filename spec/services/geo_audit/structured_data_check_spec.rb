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

  describe "#call" do
    context "when the page has Product structured data" do
      it "reports product_schema as true" do
        stub_page(<<~HTML)
          <html><head>
            <script type="application/ld+json">{"@context":"https://schema.org","@type":"Product","name":"Socks"}</script>
          </head></html>
        HTML

        result = check.call("some-handle")

        expect(result).to eq(product_schema: true, faq_schema: false, schema_types_found: [ "Product" ])
      end
    end

    context "when the page has FAQPage structured data" do
      it "reports faq_schema as true" do
        stub_page(<<~HTML)
          <html><head>
            <script type="application/ld+json">{"@context":"https://schema.org","@type":"FAQPage","mainEntity":[]}</script>
          </head></html>
        HTML

        result = check.call("some-handle")

        expect(result).to eq(product_schema: false, faq_schema: true, schema_types_found: [ "FAQPage" ])
      end
    end

    context "when the page has no structured data" do
      it "reports both as false" do
        stub_page("<html><head></head><body>No JSON-LD here</body></html>")

        result = check.call("some-handle")

        expect(result).to eq(product_schema: false, faq_schema: false, schema_types_found: [])
      end
    end

    context "when a script block contains invalid JSON" do
      it "skips it instead of raising" do
        stub_page(<<~HTML)
          <html><head>
            <script type="application/ld+json">{not valid json}</script>
            <script type="application/ld+json">{"@type":"Product"}</script>
          </head></html>
        HTML

        result = check.call("some-handle")

        expect(result).to eq(product_schema: true, faq_schema: false, schema_types_found: [ "Product" ])
      end
    end
  end
end
