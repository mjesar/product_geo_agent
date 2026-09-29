class CheckFaqMetafieldTool < LittleGhost::Tool
  tool_name "check_faq_metafield"
  description "Checks a specific product's custom.faq metafield for buyer-question content. " \
              "Only call this if check_faq_page found nothing — some stores keep FAQ content " \
              "on a per-product metafield instead of a dedicated page."

  input_schema type: "object", properties: { handle: { type: "string" } }, required: [ "handle" ], additionalProperties: false

  # The agent only ever calls one tool at a time anyway (the system prompt is
  # explicitly sequential), and marking tools exclusive keeps little_ghost from
  # dispatching them through its thread-spawning executor — needed for
  # before_tool/after_tool hooks to see the same Thread.current-scoped state
  # Auditor set up on the calling thread.
  exclusive true

  def initialize(faq_check: GeoAudit::FaqCheck.new, **kwargs)
    @faq_check = faq_check
    super(**kwargs)
  end

  def call(input)
    @faq_check.metafield(input.fetch("handle"))
  end
end
