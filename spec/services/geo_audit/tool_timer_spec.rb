require "rails_helper"

RSpec.describe GeoAudit::ToolTimer do
  it "stashes a start time in context.state keyed by the tool call's id" do
    context = LittleGhost::RunContext.new
    tool_use = LittleGhost::Content::ToolUse.new(id: "call-1", name: "get_product_data", input: {})

    described_class.new.call({ tool_use: tool_use }, context: context)

    expect(context.state.dig(described_class::STARTED_AT_KEY, "call-1")).to be_a(Float)
  end
end
