require "rails_helper"

RSpec.describe GeoAudit::Eval::Runner do
  let(:ratings) { { "description_quality" => { "rating" => "good", "reason" => "Names material." } } }
  let(:tool_results) { { "get_product_data" => { title: "Cozy Wool Socks" } } }
  let(:score) { GeoAudit::Score::Result.new(total: 82, items: []) }

  def audit_result(calls: 7)
    tracker = GeoAudit::Usage::Tracker.new
    calls.times { tracker.record_call!(:agent) }

    GeoAudit::Auditor::Result.new(
      run: instance_double(
        LittleGhost::Run,
        result: instance_double(
          LittleGhost::RunResult,
          state: tool_results,
          structured_result: instance_double(LittleGhost::StructuredResult, value: ratings)
        )
      ),
      score: score, explanation: nil, usage: tracker.snapshot, elapsed_seconds: 30.0
    )
  end

  let(:auditor) { instance_double(GeoAudit::Auditor, call: audit_result) }
  let(:sleeps) { [] }
  let(:sleeper) { ->(seconds) { sleeps << seconds } }
  # Each run reads the clock twice (start, then after the audit before pacing).
  let(:clock_times) { [ 0.0, 10.0, 10.0, 40.0, 40.0, 41.0 ] }
  let(:clock) { -> { clock_times.shift } }

  def runner(**options)
    described_class.new(auditor: auditor, clock: clock, sleeper: sleeper, **options)
  end

  it "runs the audit the requested number of times against the given handle" do
    runs = runner(runs: 3).call(handle: "cozy-wool-socks")

    expect(runs.map(&:index)).to eq([ 1, 2, 3 ])
    expect(auditor).to have_received(:call).with(handle: "cozy-wool-socks").exactly(3).times
  end

  it "collects each run's ratings, tool results, score and request count" do
    run = runner(runs: 1).call(handle: "cozy-wool-socks").first

    expect(run).to have_attributes(ratings: ratings, tool_results: tool_results, score: score, calls: 7, error: nil)
  end

  it "defaults to five runs" do
    allow(auditor).to receive(:call).and_return(audit_result)
    described_class.new(auditor: auditor, clock: -> { 0.0 }, sleeper: sleeper).call(handle: "cozy-wool-socks")

    expect(auditor).to have_received(:call).exactly(5).times
  end

  describe "pacing" do
    # 15 requests/minute is 4 seconds per request, so 7 requests need 28 seconds.
    it "waits out the rest of the time the audit's requests are owed" do
      runner(runs: 2, requests_per_minute: 15).call(handle: "cozy-wool-socks")

      expect(sleeps).to eq([ 18.0 ])
    end

    it "does not wait when the audit already took long enough" do
      times = [ 0.0, 30.0, 30.0, 60.0 ]
      described_class.new(auditor: auditor, runs: 2, clock: -> { times.shift }, sleeper: sleeper)
                     .call(handle: "cozy-wool-socks")

      expect(sleeps).to be_empty
    end

    it "does not wait after the last run" do
      runner(runs: 1).call(handle: "cozy-wool-socks")

      expect(sleeps).to be_empty
    end
  end

  describe "when an audit fails" do
    before do
      allow(auditor).to receive(:call).and_invoke(
        ->(**) { audit_result },
        ->(**) { raise "GeoAuditAgent run did not complete (failed): Gemini rate limited" },
        ->(**) { audit_result }
      )
    end

    it "keeps the failed run and carries on with the rest" do
      runs = runner(runs: 3).call(handle: "cozy-wool-socks")

      expect(runs.map(&:error)).to eq([ nil, "GeoAuditAgent run did not complete (failed): Gemini rate limited", nil ])
      expect(runs[1]).to have_attributes(ratings: nil, tool_results: nil, score: nil)
    end

    it "paces a failed run as if it used the assumed number of requests" do
      times = [ 0.0, 28.0, 28.0, 56.0, 56.0 ]
      described_class.new(auditor: auditor, runs: 3, clock: -> { times.shift }, sleeper: sleeper)
                     .call(handle: "cozy-wool-socks")

      expect(sleeps).to eq([ 4.0 ])
    end
  end

  it "stops instead of repeating when the product does not exist" do
    allow(auditor).to receive(:call).and_raise(GeoAudit::Auditor::ProductNotFound, "no product found")

    expect { runner(runs: 5).call(handle: "no-such-socks") }.to raise_error(GeoAudit::Auditor::ProductNotFound)
    expect(auditor).to have_received(:call).once
  end

  it "reports each run as it finishes" do
    seen = []

    runner(runs: 2, on_run: ->(run) { seen << run.index }).call(handle: "cozy-wool-socks")

    expect(seen).to eq([ 1, 2 ])
  end
end
