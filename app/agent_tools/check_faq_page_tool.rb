class CheckFaqPageTool < LittleGhost::Tool
  tool_name "check_faq_page"
  description "Checks whether the store has a dedicated FAQ page (e.g. /pages/faq) and returns " \
              "its content if so. Try this before check_faq_metafield — most stores that have " \
              "buyer-question content put it here first."

  input_schema type: "object", properties: {}, additionalProperties: false

  def initialize(faq_check: GeoAudit::FaqCheck.new, **kwargs)
    @faq_check = faq_check
    super(**kwargs)
  end

  def call(_input)
    @faq_check.page
  end
end
