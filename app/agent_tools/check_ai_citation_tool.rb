class CheckAiCitationTool < LittleGhost::Tool
  tool_name "check_ai_citation"
  description "Checks whether an AI assistant would organically recommend this product when " \
              "asked a natural buyer question about its category, without being told the " \
              "product's name. Run this last, once you already know the product's title and " \
              "category from get_product_data."

  input_schema type: "object", properties: {
    product_title: { type: "string" },
    category: {
      type: "string",
      description: "A natural, buyer-facing phrase for the product's category, e.g. " \
                    "'wool socks' or 'ceramic coffee mugs' — not a raw product_type or tag string."
    }
  }, required: [ "product_title", "category" ], additionalProperties: false

  def initialize(citation_check: GeoAudit::CitationCheck.new, **kwargs)
    @citation_check = citation_check
    super(**kwargs)
  end

  def call(input)
    @citation_check.call(product_title: input.fetch("product_title"), category: input.fetch("category"))
  end
end
