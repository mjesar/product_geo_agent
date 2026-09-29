require "rails_helper"

RSpec.describe GeoAudit::ModelCallLogger do
  let(:tracker) { GeoAudit::Usage::Tracker.new }
  let(:reporter) { instance_double(GeoAudit::Reporter::Null, event: nil) }
  let(:current_audit) { GeoAudit::CurrentAudit.new(tracker: tracker, reporter: reporter) }
  let(:context) { LittleGhost::RunContext.new }

  before { GeoAudit::CurrentAudit.current = current_audit }
  after { GeoAudit::CurrentAudit.current = nil }

  def response_with(*content)
    LittleGhost::ModelResponse.new(
      message: LittleGhost::Message.new(role: :assistant, content: content),
      stop_reason: :tool_use
    )
  end

  it "announces the model's tool choice, with a duration when a matching start time was recorded" do
    request = instance_double(LittleGhost::ModelRequest, messages: [])
    GeoAudit::ModelCallCounter.new.call({ turn: 1, request: request }, context: context)
    tool_use = LittleGhost::Content::ToolUse.new(id: "call-1", name: "get_product_data", input: {})

    described_class.new.call({ turn: 1, response: response_with(tool_use) }, context: context)

    expect(reporter).to have_received(:event).with(
      :agent_call_finished, hash_including(turn: 1, duration: (be >= 0), decision: "chose tool get_product_data")
    )
  end

  it "announces the raw response, for a trace reporter to write out" do
    response = response_with(LittleGhost::Content::ToolUse.new(id: "call-1", name: "get_product_data", input: {}))

    described_class.new.call({ turn: 1, response: response }, context: context)

    expect(reporter).to have_received(:event).with(:agent_call_finished, hash_including(response: response.message.to_h))
  end

  it "joins multiple tool choices from the same turn" do
    tool_uses = [
      LittleGhost::Content::ToolUse.new(id: "call-1", name: "get_product_data", input: {}),
      LittleGhost::Content::ToolUse.new(id: "call-2", name: "check_faq_page", input: {})
    ]

    described_class.new.call({ turn: 1, response: response_with(*tool_uses) }, context: context)

    expect(reporter).to have_received(:event).with(
      :agent_call_finished, hash_including(decision: "chose tools get_product_data, check_faq_page")
    )
  end

  it "announces a final answer with no tool call" do
    described_class.new.call({ turn: 1, response: response_with("all done") }, context: context)

    expect(reporter).to have_received(:event).with(
      :agent_call_finished, hash_including(decision: "answered without a tool call")
    )
  end

  it "announces a nil duration when no start time was recorded" do
    described_class.new.call({ turn: 1, response: response_with("all done") }, context: context)

    expect(reporter).to have_received(:event).with(:agent_call_finished, hash_including(duration: nil))
  end

  it "announces the tool names as a plain array, for a reporter that doesn't want to parse the sentence" do
    tool_uses = [
      LittleGhost::Content::ToolUse.new(id: "call-1", name: "get_product_data", input: {}),
      LittleGhost::Content::ToolUse.new(id: "call-2", name: "check_faq_page", input: {})
    ]

    described_class.new.call({ turn: 1, response: response_with(*tool_uses) }, context: context)

    expect(reporter).to have_received(:event).with(
      :agent_call_finished, hash_including(tool_names: [ "get_product_data", "check_faq_page" ])
    )
  end

  it "announces an empty tool_names array for a final answer with no tool call" do
    described_class.new.call({ turn: 1, response: response_with("all done") }, context: context)

    expect(reporter).to have_received(:event).with(:agent_call_finished, hash_including(tool_names: []))
  end
end
