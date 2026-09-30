require "rails_helper"

RSpec.describe GeoAudit::ToolSummary do
  subject(:summary) { described_class.new }

  describe "get_product_data" do
    it "names the product, variant count, and cheapest price" do
      value = {
        title: "The Complete Snowboard",
        variants: [
          { title: "Ice", price: { amount: "699.95", currency_code: "USD" } },
          { title: "Dawn", price: { amount: "699.95", currency_code: "USD" } }
        ]
      }

      expect(summary.call("get_product_data", value)).to eq(%("The Complete Snowboard" · 2 variants · $699.95))
    end

    it "uses the singular for exactly one variant" do
      value = { title: "Solo Item", variants: [ { title: "Only", price: { amount: "10.00" } } ] }

      expect(summary.call("get_product_data", value)).to eq(%("Solo Item" · 1 variant · $10.00))
    end

    it "leaves out the price when there are no variants" do
      value = { title: "No Variants", variants: [] }

      expect(summary.call("get_product_data", value)).to eq(%("No Variants" · 0 variants))
    end
  end

  describe "check_faq_page" do
    it "names the page when found" do
      expect(summary.call("check_faq_page", { found: true, title: "Frequently Asked Questions" })).to eq(
        %(FAQ page found: "Frequently Asked Questions")
      )
    end

    it "says so plainly when not found" do
      expect(summary.call("check_faq_page", { found: false, title: nil })).to eq("no FAQ page found")
    end
  end

  describe "check_faq_metafield" do
    it "reports found or not found" do
      expect(summary.call("check_faq_metafield", { found: true, value: "Some FAQ" })).to eq("FAQ metafield found")
      expect(summary.call("check_faq_metafield", { found: false, value: nil })).to eq("no FAQ metafield found")
    end
  end

  describe "check_structured_data" do
    it "reports both schema flags" do
      value = { product_schema: true, product_schema_complete: true, faq_schema: false, schema_types_found: [ "Product" ] }

      expect(summary.call("check_structured_data", value)).to eq("Product schema: yes · FAQ schema: no")
    end

    it "flags a Product schema that is present but incomplete" do
      value = { product_schema: true, product_schema_complete: false, faq_schema: false, schema_types_found: [ "Product" ] }

      expect(summary.call("check_structured_data", value)).to eq("Product schema: incomplete · FAQ schema: no")
    end

    it "reports no Product schema when none is present" do
      value = { product_schema: false, product_schema_complete: false, faq_schema: false, schema_types_found: [] }

      expect(summary.call("check_structured_data", value)).to eq("Product schema: no · FAQ schema: no")
    end
  end

  describe "check_ai_citation" do
    it "reports whether it was mentioned" do
      expect(summary.call("check_ai_citation", { mentioned: true })).to eq("mentioned as a recommendation")
      expect(summary.call("check_ai_citation", { mentioned: false })).to eq("not mentioned as a recommendation")
    end
  end

  it "falls back to the value's own to_s for an unrecognized tool name" do
    expect(summary.call("some_future_tool", { ok: true })).to eq({ ok: true }.to_s)
  end
end
