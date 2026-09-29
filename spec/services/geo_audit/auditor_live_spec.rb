require "rails_helper"

RSpec.describe GeoAudit::Auditor, :live do
  it "runs a full scored audit against a real sandbox product with the real Gemini model" do
    result = described_class.new.call(handle: "the-complete-snowboard")

    expect(result.run).to be_completed
    expect(result.score.items.size).to eq(7)
    expect(result.score.total).to be_between(0, 100)
    expect(result.explanation).to be_present

    # Proves the agent's own hooks actually fired during this real run, not just
    # in isolation the way their unit specs exercise them — before_model and
    # after_tool were both silently dropped by a real little_ghost bug (see
    # CLAUDE.md known limitations) until it was patched, and no unit spec could
    # have caught that, since unit specs call the hook objects directly.
    expect(result.usage.agent.calls).to be >= 4

    tool_results = result.run.result.state
    expect(tool_results).to include("get_product_data", "check_structured_data", "check_ai_citation")
    expect(tool_results["get_product_data"]).to be_present
  end
end
