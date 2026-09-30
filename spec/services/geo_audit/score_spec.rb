require "rails_helper"

RSpec.describe GeoAudit::Score do
  def tool_results(overrides = {})
    {
      get_product_data: { images: [ "wool sock detail", "wool sock top" ] },
      check_faq_page: { found: true, title: "FAQ", body: "..." },
      check_faq_metafield: { found: false, value: nil },
      check_structured_data: {
        product_schema: true, product_schema_complete: true, faq_schema: false, schema_types_found: [ "Product" ]
      },
      check_ai_citation: { mentioned: true, question: "...", response: "..." }
    }.deep_merge(overrides)
  end

  def ratings(overrides = {})
    {
      description_quality: { rating: "good", reason: "Describes material, fit, and care." },
      buyer_questions_answered: { rating: "good", reason: "Covers sizing and washing." },
      specs_clarity: { rating: "good", reason: "Every variant is clearly labeled." }
    }.deep_merge(overrides)
  end

  def item(result, key)
    result.items.find { |candidate| candidate.key == key }
  end

  describe "#call" do
    it "awards full credit across the board when everything is strong" do
      result = described_class.new(tool_results: tool_results, ratings: ratings).call

      expect(result.total).to eq(100)
    end

    it "awards zero across the board when everything is weak" do
      weak_tool_results = tool_results(
        get_product_data: { images: [ nil, nil ] },
        check_faq_page: { found: false },
        check_faq_metafield: { found: false },
        check_structured_data: { product_schema: false, product_schema_complete: false, faq_schema: false, schema_types_found: [] },
        check_ai_citation: { mentioned: false }
      )
      weak_ratings = ratings(
        description_quality: { rating: "poor", reason: "No detail beyond the title." },
        buyer_questions_answered: { rating: "poor", reason: "Doesn't answer sizing or care." },
        specs_clarity: { rating: "poor", reason: "Variants are unlabeled." }
      )

      result = described_class.new(tool_results: weak_tool_results, ratings: weak_ratings).call

      expect(result.total).to eq(0)
    end

    it "rounds a fractional total up (round-half-up on a positive total)" do
      fair_ratings = ratings(
        description_quality: { rating: "fair", reason: "Mentions material but not fit." },
        buyer_questions_answered: { rating: "fair", reason: "Covers sizing but not care." },
        specs_clarity: { rating: "fair", reason: "Variants exist but titles are generic." }
      )

      result = described_class.new(tool_results: tool_results, ratings: fair_ratings).call

      # 7.5 (description) + 10.0 (buyer questions) + 10 (alt text) + 5.0 (specs)
      # + 15 (faq) + 15 (structured data) + 15 (citation) = 77.5
      expect(result.total).to eq(78)
    end

    describe "alt_text" do
      it "gives proportional credit for partial alt-text coverage" do
        result = described_class.new(
          tool_results: tool_results(get_product_data: { images: [ "front detail", nil, "", "back detail" ] }),
          ratings: ratings
        ).call

        alt_text = item(result, :alt_text)
        expect(alt_text.points).to eq(5.0)
        expect(alt_text.detail).to eq("2 of 4 images have alt text")
      end

      it "gives zero credit when the product has no images" do
        result = described_class.new(
          tool_results: tool_results(get_product_data: { images: [] }),
          ratings: ratings
        ).call

        alt_text = item(result, :alt_text)
        expect(alt_text.points).to eq(0.0)
        expect(alt_text.detail).to eq("no images")
      end
    end

    describe "faq_content" do
      it "gives full credit when only the metafield fallback found content" do
        result = described_class.new(
          tool_results: tool_results(check_faq_page: { found: false }, check_faq_metafield: { found: true }),
          ratings: ratings
        ).call

        expect(item(result, :faq_content).points).to eq(15)
      end

      it "still scores correctly when the metafield tool was never called" do
        result = described_class.new(tool_results: tool_results.except(:check_faq_metafield), ratings: ratings).call

        expect(item(result, :faq_content).points).to eq(15)
      end

      it "gives zero credit when neither the page nor the metafield found anything" do
        result = described_class.new(
          tool_results: tool_results(check_faq_page: { found: false }, check_faq_metafield: { found: false }),
          ratings: ratings
        ).call

        expect(item(result, :faq_content).points).to eq(0)
      end
    end

    describe "structured_data" do
      it "gives zero credit when the Product schema is present but has no description or offers" do
        result = described_class.new(
          tool_results: tool_results(
            check_structured_data: {
              product_schema: true, product_schema_complete: false, faq_schema: false, schema_types_found: [ "Product" ]
            }
          ),
          ratings: ratings
        ).call

        structured_data = item(result, :structured_data)
        expect(structured_data.points).to eq(0)
        expect(structured_data.detail).to eq("Product schema is present but has no description or offers")
      end

      it "gives full credit when only the FAQPage schema is present" do
        result = described_class.new(
          tool_results: tool_results(
            check_structured_data: {
              product_schema: false, product_schema_complete: false, faq_schema: true, schema_types_found: [ "FAQPage" ]
            }
          ),
          ratings: ratings
        ).call

        expect(item(result, :structured_data).points).to eq(15)
      end

      it "gives zero credit when no schema is present" do
        result = described_class.new(
          tool_results: tool_results(
            check_structured_data: { product_schema: false, product_schema_complete: false, faq_schema: false, schema_types_found: [] }
          ),
          ratings: ratings
        ).call

        structured_data = item(result, :structured_data)
        expect(structured_data.points).to eq(0)
        expect(structured_data.detail).to eq("no Product/FAQPage structured data found")
      end
    end

    it "carries the model's own reason forward as a rating item's detail" do
      result = described_class.new(tool_results: tool_results, ratings: ratings).call

      expect(item(result, :description_quality).detail).to eq("rated good: Describes material, fit, and care.")
    end

    it "returns all seven rubric items, in rubric order, with their fixed weights" do
      result = described_class.new(tool_results: tool_results, ratings: ratings).call

      expect(result.items.map(&:key)).to eq(
        %i[description_quality buyer_questions_answered alt_text specs_clarity faq_content structured_data ai_citation]
      )
      expect(result.items.map(&:weight)).to eq([ 15, 20, 10, 10, 15, 15, 15 ])
    end
  end
end
