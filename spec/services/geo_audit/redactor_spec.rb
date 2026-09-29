require "rails_helper"

RSpec.describe GeoAudit::Redactor do
  describe "redacting by ENV value" do
    around do |example|
      original = ENV.to_h.slice(*GeoAudit::Redactor::ENV_KEYS)
      ENV["GEMINI_API_KEY"] = "fake-gemini-key-123"
      ENV["SHOPIFY_STOREFRONT_TOKEN"] = "fake-storefront-token-456"
      ENV["SHOPIFY_STOREFRONT_PASSWORD"] = "fake-password-789"
      example.run
      GeoAudit::Redactor::ENV_KEYS.each { |key| ENV[key] = original[key] }
    end

    it "redacts a known secret value found inside a string" do
      redactor = described_class.new
      text = "Authorization used key fake-gemini-key-123 for the request"

      expect(redactor.redact(text)).to eq("Authorization used key [REDACTED] for the request")
    end

    it "redacts every configured secret in the same string, not just the first" do
      redactor = described_class.new
      text = "token=fake-storefront-token-456 password=fake-password-789"

      expect(redactor.redact(text)).to eq("token=[REDACTED] password=[REDACTED]")
    end

    it "leaves text with no secrets in it untouched" do
      redactor = described_class.new

      expect(redactor.redact("nothing sensitive here")).to eq("nothing sensitive here")
    end
  end

  describe "redacting by field name" do
    it "redacts hash values whose key looks sensitive, regardless of the value" do
      redactor = described_class.new(secrets: [])

      result = redactor.redact({ api_key: "sk-something-unexpected", handle: "cozy-wool-socks" })

      expect(result).to eq(api_key: "[REDACTED]", handle: "cozy-wool-socks")
    end

    it "matches sensitive-looking string keys too, not just symbols" do
      redactor = described_class.new(secrets: [])

      result = redactor.redact({ "X-Shopify-Storefront-Access-Token" => "whatever" })

      expect(result).to eq("X-Shopify-Storefront-Access-Token" => "[REDACTED]")
    end

    it "redacts inside nested hashes and arrays" do
      redactor = described_class.new(secrets: [])

      result = redactor.redact(
        { headers: { "Authorization-Token" => "whatever" }, items: [ { password: "x" }, { handle: "y" } ] }
      )

      expect(result).to eq(
        headers: { "Authorization-Token" => "[REDACTED]" },
        items: [ { password: "[REDACTED]" }, { handle: "y" } ]
      )
    end
  end

  it "leaves ordinary values untouched" do
    redactor = described_class.new(secrets: [])

    expect(redactor.redact({ handle: "cozy-wool-socks", count: 3 })).to eq(handle: "cozy-wool-socks", count: 3)
  end
end
