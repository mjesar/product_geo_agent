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

    it "tells the model not to calculate a score itself" do
      expect(prompt).to match(/Do not calculate or mention a numeric\s+score/)
    end

    it "explains what poor, fair, and good mean for each qualitative item" do
      expect(prompt).to match(/description_quality/)
      expect(prompt).to match(/buyer_questions_answered/)
      expect(prompt).to match(/specs_clarity/)
    end
  end

  describe "result_schema" do
    let(:schema) { described_class.result_schema.fetch(:schema) }

    it "requires a poor/fair/good rating and a reason for each qualitative item" do
      expect(schema["required"]).to match_array(
        %w[description_quality buyer_questions_answered specs_clarity]
      )

      rating_property = schema.dig("properties", "description_quality")
      expect(rating_property["required"]).to match_array(%w[rating reason])
      expect(rating_property.dig("properties", "rating", "enum")).to eq(%w[poor fair good])
    end
  end
end
