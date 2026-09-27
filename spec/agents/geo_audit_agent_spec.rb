require "rails_helper"

RSpec.describe GeoAuditAgent do
  it "registers all five geo-audit tools" do
    expect(described_class.tool_declarations).to match_array(
      [ GetProductDataTool, CheckFaqPageTool, CheckFaqMetafieldTool, CheckStructuredDataTool, CheckAiCitationTool ]
    )
  end

  it "targets the working Gemini model" do
    expect(described_class.model).to eq("gemini:gemini-flash-lite-latest")
  end

  describe "system prompt" do
    let(:prompt) { File.read(Rails.root.join("app/prompts/geo_audit/system_prompt.erb")) }

    it "starts with get_product_data before anything else" do
      expect(prompt).to match(/Always call get_product_data first/)
    end

    it "tries check_faq_page before falling back to check_faq_metafield" do
      expect(prompt).to match(/check_faq_page/)
      expect(prompt).to match(/check_faq_metafield/)
      expect(prompt.index("check_faq_page")).to be < prompt.index("check_faq_metafield")
    end

    it "runs check_ai_citation last, without naming the product in the question" do
      expect(prompt).to match(/check_ai_citation last/)
      expect(prompt).to match(/Never pass the product's own name/)
    end

    it "encodes the scoring rubric out of 100" do
      expect(prompt).to match(/out of 100/)
      expect(prompt).to match(/Description quality\/length/)
    end
  end
end
