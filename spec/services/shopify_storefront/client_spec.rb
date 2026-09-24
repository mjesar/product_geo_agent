require "rails_helper"

RSpec.describe ShopifyStorefront::Client do
  let(:store_domain) { "test-store.myshopify.com" }
  let(:token) { "shpat_test_token" }
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:graphql_path) { "/api/#{described_class::API_VERSION}/graphql.json" }
  let(:test_connection) do
    Faraday.new(url: "https://#{store_domain}/api/#{described_class::API_VERSION}/") do |builder|
      builder.adapter :test, stubs
    end
  end
  let(:client) do
    described_class.new(store_domain: store_domain, token: token, connection: test_connection)
  end

  describe "#query" do
    it "returns the parsed data on a successful response" do
      stubs.post(graphql_path) do |env|
        expect(env.request_headers["X-Shopify-Storefront-Access-Token"]).to eq(token)
        expect(env.request_headers["Content-Type"]).to eq("application/json")
        expect(JSON.parse(env.body)["query"]).to eq("{ shop { name } }")

        [
          200,
          { "Content-Type" => "application/json" },
          { data: { shop: { name: "Test Shop" } } }.to_json
        ]
      end

      result = client.query("{ shop { name } }")

      expect(result).to eq("shop" => { "name" => "Test Shop" })
      stubs.verify_stubbed_calls
    end

    it "passes variables through in the request body" do
      stubs.post(graphql_path) do |env|
        expect(JSON.parse(env.body)["variables"]).to eq("handle" => "a-product")

        [ 200, {}, { data: {} }.to_json ]
      end

      client.query("query($handle: String) { product(handle: $handle) { id } }", variables: { handle: "a-product" })

      stubs.verify_stubbed_calls
    end

    it "raises a Client::Error when the API returns GraphQL-level errors" do
      stubs.post(graphql_path) do
        [
          200,
          { "Content-Type" => "application/json" },
          { errors: [ { message: "Field 'nope' doesn't exist" } ] }.to_json
        ]
      end

      expect { client.query("{ nope }") }
        .to raise_error(ShopifyStorefront::Client::Error, /Field 'nope' doesn't exist/)
    end

    it "raises a Client::Error on an HTTP-level failure" do
      stubs.post(graphql_path) do
        [ 401, {}, "Unauthorized" ]
      end

      expect { client.query("{ shop { name } }") }
        .to raise_error(ShopifyStorefront::Client::Error, /401/)
    end
  end
end
