class GeoAuditAgent < LittleGhost::Agent
  model "gemini:gemini-flash-lite-latest"

  tools GetProductDataTool, CheckFaqPageTool, CheckFaqMetafieldTool, CheckStructuredDataTool, CheckAiCitationTool
end
