require "rails_helper"

RSpec.describe GeoAudit::ModelCallCounter do
  after { GeoAudit::CurrentAudit.current = nil }

  it "records an agent call and announces it to the reporter" do
    tracker = GeoAudit::Usage::Tracker.new
    reporter = instance_double(GeoAudit::Reporter::Null, event: nil)
    GeoAudit::CurrentAudit.current = GeoAudit::CurrentAudit.new(tracker: tracker, reporter: reporter)

    described_class.new.call({ turn: 1 }, context: LittleGhost::RunContext.new)

    expect(tracker.snapshot.agent.calls).to eq(1)
    expect(reporter).to have_received(:event).with(:agent_call_started, turn: 1)
  end

  it "fails loudly when no current audit has been set" do
    expect { described_class.new.call({ turn: 1 }, context: LittleGhost::RunContext.new) }.to raise_error(
      GeoAudit::CurrentAudit::MissingError
    )
  end
end
