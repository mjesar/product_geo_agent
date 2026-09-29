require "rails_helper"

RSpec.describe GeoAudit::ModelCallCounter do
  after { GeoAudit::CurrentAudit.current = nil }

  let(:message) { LittleGhost::Message.new(role: :user, content: "Audit this product") }
  let(:request) { instance_double(LittleGhost::ModelRequest, messages: [ message ]) }

  def payload
    { turn: 1, request: request }
  end

  it "records an agent call and announces it to the reporter" do
    tracker = GeoAudit::Usage::Tracker.new
    reporter = instance_double(GeoAudit::Reporter::Null, event: nil)
    GeoAudit::CurrentAudit.current = GeoAudit::CurrentAudit.new(tracker: tracker, reporter: reporter)

    described_class.new.call(payload, context: LittleGhost::RunContext.new)

    expect(tracker.snapshot.agent.calls).to eq(1)
    expect(reporter).to have_received(:event).with(:agent_call_started, turn: 1, request: [ message.to_h ])
  end

  it "fails loudly when no current audit has been set" do
    expect { described_class.new.call(payload, context: LittleGhost::RunContext.new) }.to raise_error(
      GeoAudit::CurrentAudit::MissingError
    )
  end
end
