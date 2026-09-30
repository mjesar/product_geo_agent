module GeoAudit
  # Turns a tool's raw return value into one short, human sentence for the
  # terminal reporter — the raw value itself (value.to_s) was never meant to be
  # read directly, it's a full Ruby hash dump.
  class ToolSummary
    def call(name, value)
      case name
      when "get_product_data" then product_data(value)
      when "check_faq_page" then faq_page(value)
      when "check_faq_metafield" then faq_metafield(value)
      when "check_structured_data" then structured_data(value)
      when "check_ai_citation" then ai_citation(value)
      else value.to_s
      end
    end

    private

    def product_data(value)
      variants = value[:variants] || []
      price = variants.first&.dig(:price, :amount)
      count = variants.size
      %("#{value[:title]}" · #{count} variant#{"s" unless count == 1}#{" · $#{price}" if price})
    end

    def faq_page(value)
      value[:found] ? %(FAQ page found: "#{value[:title]}") : "no FAQ page found"
    end

    def faq_metafield(value)
      value[:found] ? "FAQ metafield found" : "no FAQ metafield found"
    end

    def structured_data(value)
      product =
        if value[:product_schema_complete] then "yes"
        elsif value[:product_schema] then "incomplete"
        else "no"
        end

      "Product schema: #{product} · FAQ schema: #{value[:faq_schema] ? "yes" : "no"}"
    end

    def ai_citation(value)
      value[:mentioned] ? "mentioned as a recommendation" : "not mentioned as a recommendation"
    end
  end
end
