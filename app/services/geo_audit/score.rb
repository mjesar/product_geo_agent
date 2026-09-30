module GeoAudit
  class Score
    WEIGHTS = {
      description_quality: 15,
      buyer_questions_answered: 20,
      alt_text: 10,
      specs_clarity: 10,
      faq_content: 15,
      structured_data: 15,
      ai_citation: 15
    }.freeze

    RATING_POINTS = { "poor" => 0.0, "fair" => 0.5, "good" => 1.0 }.freeze

    Item = Data.define(:key, :label, :weight, :points, :detail)
    Result = Data.define(:total, :items)

    def initialize(tool_results:, ratings:)
      @tool_results = tool_results.deep_symbolize_keys
      @ratings = ratings.deep_symbolize_keys
    end

    def call
      items = [
        rating_item(:description_quality, "Description quality/length"),
        rating_item(:buyer_questions_answered, "Answers common buyer questions"),
        alt_text_item,
        rating_item(:specs_clarity, "Clear specs/variants"),
        faq_content_item,
        structured_data_item,
        ai_citation_item
      ]

      # Sum first, round once — rounding each item first and then summing can
      # drift from rounding the total a single time. Float#round with no
      # argument rounds a halfway total away from zero (87.5 => 88).
      Result.new(total: items.sum(&:points).round, items:)
    end

    private

    def rating_item(key, label)
      rating = @ratings.dig(key, :rating)
      reason = @ratings.dig(key, :reason)
      weight = WEIGHTS.fetch(key)
      fraction = RATING_POINTS.fetch(rating)

      Item.new(key:, label:, weight:, points: weight * fraction, detail: "rated #{rating}: #{reason}")
    end

    def alt_text_item
      images = @tool_results.dig(:get_product_data, :images) || []
      weight = WEIGHTS.fetch(:alt_text)
      with_alt = images.count { |alt_text| alt_text.present? }
      fraction = images.empty? ? 1.0 : with_alt / images.size.to_f
      detail = images.empty? ? "no images to check" : "#{with_alt} of #{images.size} images have alt text"

      Item.new(key: :alt_text, label: "Alt text on images", weight:, points: weight * fraction, detail:)
    end

    def faq_content_item
      found = @tool_results.dig(:check_faq_page, :found) || @tool_results.dig(:check_faq_metafield, :found)

      boolean_item(
        :faq_content, "FAQ content (page or metafield)", found:,
        detail_true: "FAQ content found", detail_false: "no FAQ page or metafield found"
      )
    end

    def structured_data_item
      result = @tool_results.fetch(:check_structured_data, {})
      found = result[:product_schema_complete] || result[:faq_schema]

      boolean_item(
        :structured_data, "Structured data (Product/FAQPage)", found:,
        detail_true: "structured data found: #{Array(result[:schema_types_found]).join(', ')}",
        detail_false: "no Product/FAQPage structured data found"
      )
    end

    def ai_citation_item
      found = @tool_results.dig(:check_ai_citation, :mentioned)

      boolean_item(
        :ai_citation, "AI citation check", found:,
        detail_true: "AI assistant mentioned this product unprompted",
        detail_false: "AI assistant did not mention this product"
      )
    end

    def boolean_item(key, label, found:, detail_true:, detail_false:)
      weight = WEIGHTS.fetch(key)

      Item.new(key:, label:, weight:, points: found ? weight : 0, detail: found ? detail_true : detail_false)
    end
  end
end
