class CheckStructuredDataTool < LittleGhost::Tool
  tool_name "check_structured_data"
  description "Fetches the live product page and checks for Product/FAQPage structured " \
              "data (JSON-LD schema.org markup). AI shopping assistants and search engines " \
              "rely on this markup to understand and cite product pages accurately."

  input_schema type: "object", properties: { handle: { type: "string" } }, required: [ "handle" ], additionalProperties: false

  def initialize(structured_data_check: GeoAudit::StructuredDataCheck.new, **kwargs)
    @structured_data_check = structured_data_check
    super(**kwargs)
  end

  def call(input)
    @structured_data_check.call(input.fetch("handle"))
  end
end
