class GeoAuditAgent < LittleGhost::Agent
  model GeoAudit::Models.for(:agent)

  tools GetProductDataTool, CheckFaqPageTool, CheckFaqMetafieldTool, CheckStructuredDataTool, CheckAiCitationTool

  RATING = {
    type: "object",
    properties: {
      rating: { type: "string", enum: %w[poor fair good] },
      reason: { type: "string" }
    },
    required: %w[rating reason],
    additionalProperties: false
  }.freeze

  result_schema(
    name: "geo_audit_ratings",
    description: "Categorical judgment for the rubric's three qualitative items, each with a " \
                 "one-sentence reason. Ruby derives the numeric score from these ratings plus " \
                 "the tool results already gathered — do not calculate or mention a score here.",
    type: "object",
    properties: {
      description_quality: RATING,
      buyer_questions_answered: RATING,
      specs_clarity: RATING
    },
    required: %w[description_quality buyer_questions_answered specs_clarity],
    additionalProperties: false
  )

  after_tool do |payload, context:|
    context.state[payload[:tool_use].name] = payload[:result].value
  end

  after_model_error GeoAudit::ModelErrorRecovery.new
end
