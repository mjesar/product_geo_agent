class CheckFaqMetafieldTool < LittleGhost::Tool
  tool_name "check_faq_metafield"
  description "Checks a specific product's custom.faq metafield for buyer-question content. " \
              "Only call this if check_faq_page found nothing — some stores keep FAQ content " \
              "on a per-product metafield instead of a dedicated page."

  input_schema type: "object", properties: { handle: { type: "string" } }, required: [ "handle" ], additionalProperties: false

  def initialize(faq_check: GeoAudit::FaqCheck.new, **kwargs)
    @faq_check = faq_check
    super(**kwargs)
  end

  def call(input)
    @faq_check.metafield(input.fetch("handle"))
  end
end
