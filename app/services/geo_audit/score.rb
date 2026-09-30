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

    Item = Data.define(:key, :label, :weight, :points, :detail) do
      # Points this item failed to earn. Computed here in Ruby so the explanation
      # never has to subtract (or add) numbers itself. Rounded to one decimal
      # because partial credit can produce float noise (3.3333333333333335), and
      # whole numbers come back as integers so they print as "10", not "10.0".
      def lost
        missing = (weight - points).round(1)
        (missing == missing.to_i) ? missing.to_i : missing
      end
    end

    Result = Data.define(:total, :items) do
      # Only the items that lost points, biggest loss first. Ties keep rubric
      # order: sort_by isn't stable in Ruby, so the original index is part of
      # the sort key to keep the order the same from run to run.
      def gaps
        items.each_with_index
             .select { |item, _index| item.lost.positive? }
             .sort_by { |item, index| [ -item.lost, index ] }
             .map(&:first)
      end

      # Derived from the rounded total, not by summing each item's loss, so the
      # two headline numbers always add up to 100 (77.5 rounds to 78, and summing
      # the items' losses would say 22.5, which is 101 together).
      def total_lost
        WEIGHTS.values.sum - total
      end
    end

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
      # No images means nothing for an AI assistant to read or describe, which
      # is worse for discoverability than images without alt text, not neutral.
      fraction = images.empty? ? 0.0 : with_alt / images.size.to_f
      detail = images.empty? ? "no images" : "#{with_alt} of #{images.size} images have alt text"

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

      # An empty Product block is a different fix (fill in the product's own
      # description) from no markup at all (add schema), so say which one it is.
      detail_false =
        if result[:product_schema]
          "Product schema is present but has no description or offers"
        else
          "no Product/FAQPage structured data found"
        end

      boolean_item(
        :structured_data, "Structured data (Product/FAQPage)", found:,
        detail_true: "structured data found: #{Array(result[:schema_types_found]).join(', ')}",
        detail_false:
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
