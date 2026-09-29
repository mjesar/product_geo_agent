require "rails_helper"

RSpec.describe GeoAudit::ModelErrorRecovery do
  def http_error(status)
    LittleGhost::Providers::HTTPError.new("boom", status: status, body: "{}")
  end

  let(:sleeps) { [] }
  let(:sleeper) { ->(seconds) { sleeps << seconds } }
  let(:recovery) { described_class.new(sleeper: sleeper) }
  let(:tracker) { GeoAudit::Usage::Tracker.new }
  let(:reporter) { instance_double(GeoAudit::Reporter::Null, event: nil) }
  let(:current_audit) { GeoAudit::CurrentAudit.new(tracker: tracker, reporter: reporter) }
  let(:context) { LittleGhost::RunContext.new }
  let(:request) { double("ModelRequest") }

  before { GeoAudit::CurrentAudit.current = current_audit }
  after { GeoAudit::CurrentAudit.current = nil }

  def payload(turn:, status:)
    { request: request, error: http_error(status), turn: turn, parent_operation_id: nil }
  end

  it "replaces the request with itself to trigger a retry on a retryable error" do
    decision = recovery.call(payload(turn: 1, status: 503), context: context)

    expect(decision).to be_a(LittleGhost::Support::Callbacks::Replace)
    expect(decision.value).to eq(request: request)
    expect(sleeps).to eq([5])
  end

  it "records the retry on the tracker and announces it to the reporter before sleeping" do
    log = []
    ordering_reporter = instance_double(GeoAudit::Reporter::Null)
    allow(ordering_reporter).to receive(:event) { |name, **data| log << [ :event, name, data ] }
    GeoAudit::CurrentAudit.current = GeoAudit::CurrentAudit.new(tracker: tracker, reporter: ordering_reporter)
    ordering_sleeper = ->(seconds) { log << [ :sleep, seconds ] }
    ordering_recovery = described_class.new(sleeper: ordering_sleeper)

    ordering_recovery.call(payload(turn: 1, status: 503), context: context)

    expect(tracker.snapshot.agent.retries).to eq(1)
    expect(log).to eq([
      [ :event, :retry, { part: :agent, attempt: 1, delay: 5, status: 503, reason: "boom" } ],
      [ :sleep, 5 ]
    ])
  end

  it "returns nil without sleeping when the error isn't retryable" do
    decision = recovery.call(payload(turn: 1, status: 400), context: context)

    expect(decision).to be_nil
    expect(sleeps).to eq([])
  end

  it "escalates the backoff for consecutive failures within the same turn, then stops" do
    recovery.call(payload(turn: 1, status: 503), context: context)
    recovery.call(payload(turn: 1, status: 503), context: context)
    decision = recovery.call(payload(turn: 1, status: 503), context: context)
    fourth_decision = recovery.call(payload(turn: 1, status: 503), context: context)

    expect(sleeps).to eq([5, 15, 30])
    expect(decision).to be_a(LittleGhost::Support::Callbacks::Replace)
    expect(fourth_decision).to be_nil
  end

  it "restarts the backoff schedule for a later, unrelated turn" do
    3.times { recovery.call(payload(turn: 1, status: 503), context: context) }
    sleeps.clear

    recovery.call(payload(turn: 2, status: 503), context: context)

    expect(sleeps).to eq([5])
  end
end
