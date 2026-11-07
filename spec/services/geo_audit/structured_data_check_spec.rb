require "rails_helper"

RSpec.describe GeoAudit::StructuredDataCheck do
  let(:connection) { instance_double(Faraday::Connection) }
  let(:password_auth) { instance_double(ShopifyStorefront::PasswordAuth, authenticated_connection: connection) }
  let(:check) { described_class.new(password_auth: password_auth) }

  def stub_page(html)
    allow(connection).to receive(:get)
      .with("products/some-handle")
      .and_return(instance_double(Faraday::Response, body: html, status: 200, success?: true))
  end

  def stub_error_page(status)
    allow(connection).to receive(:get)
      .with("products/some-handle")
      .and_return(instance_double(Faraday::Response, body: "<html>error</html>", status: status, success?: false))
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

    [ 302, 404, 429, 503 ].each do |status|
      context "when the page fetch returns HTTP #{status}" do
        it "raises instead of reporting that the page has no structured data" do
          stub_error_page(status)

          expect { check.call("some-handle") }
            .to raise_error(described_class::Error, /some-handle returned HTTP #{status}/)
        end
      end
    end

    context "with a handle that tries to leave the products path" do
      # A real connection, so these assert the URL Faraday actually builds and
      # requests, not just the string passed to #get.
      let(:requested_urls) { [] }
      let(:connection) do
        urls = requested_urls
        Faraday.new(url: "https://store.example/") do |builder|
          builder.adapter(:test) do |stub|
            stub.get(/.*/) do |env|
              urls << env.url.to_s
              [ 200, {}, "<html></html>" ]
            end
          end
        end
      end

      {
        "../admin" => "https://store.example/products/..%2Fadmin",
        "../../password" => "https://store.example/products/..%2F..%2Fpassword",
        "x?y=1" => "https://store.example/products/x%3Fy%3D1",
        "x#frag" => "https://store.example/products/x%23frag",
        "https://evil.test/a" => "https://store.example/products/https%3A%2F%2Fevil.test%2Fa"
      }.each do |handle, expected_url|
        it "keeps #{handle.inspect} inside the products path" do
          check.call(handle)

          expect(requested_urls).to eq([ expected_url ])
        end
      end

      it "leaves an ordinary handle unchanged" do
        check.call("cozy-wool-socks")

        expect(requested_urls).to eq([ "https://store.example/products/cozy-wool-socks" ])
      end

      [ "", ".", "..", "..." ].each do |handle|
        it "rejects #{handle.inspect} without making a request" do
          expect { check.call(handle) }.to raise_error(described_class::Error, /Invalid product handle/)
          expect(requested_urls).to be_empty
        end
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
