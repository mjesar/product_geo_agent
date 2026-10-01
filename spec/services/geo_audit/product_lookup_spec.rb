require "rails_helper"

RSpec.describe GeoAudit::ProductLookup do
  let(:client) { instance_double(ShopifyStorefront::Client) }

  subject(:lookup) { described_class.new(client: client) }

  it "is true when the Storefront API returns a product" do
    allow(client).to receive(:query).and_return({ "product" => { "id" => "gid://shopify/Product/1" } })

    expect(lookup.exists?("cozy-wool-socks")).to be(true)
    expect(client).to have_received(:query).with(described_class::QUERY, variables: { handle: "cozy-wool-socks" })
  end

  it "is false when the Storefront API returns a null product" do
    allow(client).to receive(:query).and_return({ "product" => nil })

    expect(lookup.exists?("no-such-socks")).to be(false)
  end

  it "lets a Storefront error propagate rather than reporting the product as missing" do
    allow(client).to receive(:query).and_raise(ShopifyStorefront::Client::Error, "401 unauthorized")

    expect { lookup.exists?("cozy-wool-socks") }.to raise_error(ShopifyStorefront::Client::Error)
  end
end
