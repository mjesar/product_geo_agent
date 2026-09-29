require "rails_helper"

RSpec.describe GeoAudit::Reporter::Terminal do
  let(:io) { StringIO.new }

  def reporter(times, redactor: GeoAudit::Redactor.new(secrets: []))
    clock_times = times.dup
    described_class.new(io: io, clock: -> { clock_times.shift }, redactor: redactor)
  end

  def output
    io.string.lines.map(&:chomp)
  end

  it "prints the audit header without a timestamp" do
    reporter([0.0]).event(:start, handle: "cozy-wool-socks", model: "gemini-flash-lite-latest")

    expect(output).to eq([ "Audit: cozy-wool-socks   (model: gemini-flash-lite-latest)" ])
  end

  it "numbers successive Gemini calls and timestamps them relative to start" do
    r = reporter([0.0, 0.0, 14.0])
    r.event(:start, handle: "cozy-wool-socks", model: "gemini-flash-lite-latest")
    r.event(:agent_call_started, turn: 1)
    r.event(:agent_call_started, turn: 2)

    expect(output).to eq([
      "Audit: cozy-wool-socks   (model: gemini-flash-lite-latest)",
      "[00:00.0] Gemini call 1: asking what to do next",
      "[00:14.0] Gemini call 2: asking what to do next"
    ])
  end

  it "shows the model's decision and how long the call took" do
    r = reporter([0.0, 1.2])
    r.event(:start, handle: "cozy-wool-socks", model: "gemini-flash-lite-latest")
    r.event(:agent_call_finished, turn: 1, duration: 1.2, decision: "chose tool get_product_data")

    expect(output.last).to eq('[00:01.2]   chose tool get_product_data  (1.2s)')
  end

  it "shows a tool's result summary" do
    r = reporter([0.0, 1.6])
    r.event(:start, handle: "cozy-wool-socks", model: "gemini-flash-lite-latest")
    r.event(:tool_finished, name: "get_product_data", duration: 0.4, summary: "3 variants, 2 images")

    expect(output.last).to eq("[00:01.6] Tool get_product_data: 3 variants, 2 images")
  end

  it "flags a retry with the reason" do
    r = reporter([0.0, 14.0])
    r.event(:start, handle: "cozy-wool-socks", model: "gemini-flash-lite-latest")
    r.event(:retry, part: :agent, attempt: 1, delay: 5, status: 503, reason: "boom")

    expect(output.last).to eq("[00:14.0] !! agent busy (503), retrying in 5s (attempt 1): boom")
  end

  it "shows the computed total score" do
    r = reporter([0.0, 22.3])
    r.event(:start, handle: "cozy-wool-socks", model: "gemini-flash-lite-latest")
    r.event(:score_computed, result: GeoAudit::Score::Result.new(total: 42, items: []))

    expect(output.last).to eq("[00:22.3] Ruby calculates the score: TOTAL 42/100")
  end

  it "flags a failed step with its reason" do
    r = reporter([0.0, 25.0])
    r.event(:start, handle: "cozy-wool-socks", model: "gemini-flash-lite-latest")
    r.event(:failure, step: "get_product_data", reason: "product not found")

    expect(output.last).to eq("[00:25.0] !! get_product_data failed: product not found")
  end

  it "prints the usage summary without a timestamp" do
    r = reporter([0.0])
    r.event(:start, handle: "cozy-wool-socks", model: "gemini-flash-lite-latest")
    snapshot = GeoAudit::Usage::Tracker.new.tap do |tracker|
      tracker.record_call!(:agent)
      tracker.record_tokens(:agent, instance_double(LittleGhost::Usage, input_tokens: 14_200, output_tokens: 1_850))
    end.snapshot

    r.event(:usage_summary, snapshot: snapshot, elapsed: 23.0)

    expect(output.last).to eq("Usage: 1 calls, 14200 tokens in, 1850 out, 23.0s")
  end

  it "silently ignores an unrecognized event name instead of raising" do
    r = reporter([0.0])
    r.event(:start, handle: "cozy-wool-socks", model: "gemini-flash-lite-latest")

    expect { r.event(:something_new, foo: "bar") }.not_to raise_error
  end

  it "never lets a secret reach the output, even nested inside event data" do
    redactor = GeoAudit::Redactor.new(secrets: [ "super-secret-body" ])
    r = reporter([0.0, 14.0], redactor: redactor)
    r.event(:start, handle: "cozy-wool-socks", model: "gemini-flash-lite-latest")

    r.event(:retry, part: :agent, attempt: 1, delay: 5, status: 429, reason: "super-secret-body")

    expect(io.string).not_to include("super-secret-body")
    expect(io.string).to include("[REDACTED]")
  end
end
