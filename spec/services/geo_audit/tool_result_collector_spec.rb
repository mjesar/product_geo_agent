require "rails_helper"

RSpec.describe GeoAudit::ToolResultCollector do
  let(:tool_use) { LittleGhost::Content::ToolUse.new(id: "call-1", name: "get_product_data", input: {}) }
  let(:result) { LittleGhost::Tool::ExecutionResult.new(value: { title: "Cozy Wool Socks" }, status: :success) }
  let(:tracker) { GeoAudit::Usage::Tracker.new }
  let(:reporter) { instance_double(GeoAudit::Reporter::Null, event: nil) }
  let(:current_audit) { GeoAudit::CurrentAudit.new(tracker: tracker, reporter: reporter) }
  let(:context) { LittleGhost::RunContext.new }

  before { GeoAudit::CurrentAudit.current = current_audit }
  after { GeoAudit::CurrentAudit.current = nil }

  def payload
    { tool_use: tool_use, tool: nil, operation_id: "op-1", parent_operation_id: nil, result: result }
  end

  it "writes the tool's result into context.state, for Score to read on the success path" do
    described_class.new.call(payload, context: context)

    # context.state stores JSON-shaped data, so keys come back as strings — Score
    # already deep_symbolize_keys's this on the way in, unrelated to this change.
    expect(context.state["get_product_data"]).to eq("title" => "Cozy Wool Socks")
  end

  it "records the same result on the current audit, for reading back even after a failed run" do
    described_class.new.call(payload, context: context)

    expect(current_audit.tool_results).to eq("get_product_data" => { title: "Cozy Wool Socks" })
  end

  it "announces the tool's finish, with a duration when a matching start time was recorded" do
    GeoAudit::ToolTimer.new.call({ tool_use: tool_use }, context: context)

    described_class.new.call(payload, context: context)

    expect(reporter).to have_received(:event).with(
      :tool_finished, name: "get_product_data", duration: (be >= 0), summary: a_string_including("Cozy Wool Socks")
    )
  end

  it "announces a nil duration when no start time was recorded" do
    described_class.new.call(payload, context: context)

    expect(reporter).to have_received(:event).with(:tool_finished, hash_including(duration: nil))
  end
end
