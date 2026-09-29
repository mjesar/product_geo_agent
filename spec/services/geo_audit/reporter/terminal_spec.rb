require "rails_helper"

RSpec.describe GeoAudit::Reporter::Terminal do
  let(:io) { StringIO.new }

  def reporter(redactor: GeoAudit::Redactor.new(secrets: []), verbose: false, color: false)
    described_class.new(io: io, redactor: redactor, verbose: verbose, color: color)
  end

  def output
    io.string.lines.map(&:chomp)
  end

  it "prints a boxed header with the handle and model" do
    reporter.event(:start, handle: "cozy-wool-socks", model: "gemini-flash-lite-latest")

    expect(output).to eq([
      "━" * 60,
      "  Auditing: cozy-wool-socks",
      "  Model: gemini-flash-lite-latest",
      "━" * 60
    ])
  end

  it "shows a thinking line with the model's duration" do
    reporter.event(:agent_call_finished, turn: 1, duration: 1.2, decision: "chose tool get_product_data", tool_names: [ "get_product_data" ])

    expect(output.last).to include("Thinking...")
    expect(output.last).to include("(1.2s)")
  end

  it "shows reasoning complete right away when the turn chose no tool" do
    reporter.event(:agent_call_finished, turn: 1, duration: 2.2, decision: "answered without a tool call", tool_names: [])

    expect(output).to eq([
      "→ Thinking...                                        (2.2s)",
      "  ✓ Reasoning complete"
    ])
  end

  it "shows a tool's human summary, not the raw value" do
    reporter.event(:tool_finished, name: "get_product_data", duration: 0.4, summary: %("Cozy Wool Socks" · 1 variant))

    expect(output.last).to eq(%(  ✓ get_product_data → "Cozy Wool Socks" · 1 variant))
  end

  it "leaves out the raw input and result in default mode, even when the event carries them" do
    reporter.event(
      :tool_finished, name: "get_product_data", duration: 0.4, summary: "ok",
      input: { handle: "cozy-wool-socks" }, result: { title: "Cozy Wool Socks" }
    )

    expect(output).to eq([ "  ✓ get_product_data → ok" ])
  end

  it "shows a tool's raw input and result in verbose mode, underneath the summary" do
    r = reporter(verbose: true)
    r.event(
      :tool_finished, name: "get_product_data", duration: 0.4, summary: "ok",
      input: { handle: "cozy-wool-socks" }, result: { title: "Cozy Wool Socks" }
    )

    expect(output).to eq([
      "  ✓ get_product_data → ok",
      '    input: {handle: "cozy-wool-socks"}',
      '    result: {title: "Cozy Wool Socks"}'
    ])
  end

  it "redacts secrets inside a verbose tool's input and result" do
    redactor = GeoAudit::Redactor.new(secrets: [ "super-secret-token" ])
    r = reporter(redactor: redactor, verbose: true)

    r.event(:tool_finished, name: "get_product_data", duration: 0.4, summary: "ok", input: {}, result: { token: "super-secret-token" })

    expect(io.string).not_to include("super-secret-token")
    expect(io.string).to include("[REDACTED]")
  end

  it "flags a retry with the reason" do
    reporter.event(:retry, part: :agent, attempt: 1, delay: 5, status: 503, reason: "boom")

    expect(output.last).to eq("  ⚠ agent busy (503) — retrying in 5s (attempt 1): boom")
  end

  it "opens the closing box and shows the total score" do
    reporter.event(:score_computed, result: GeoAudit::Score::Result.new(total: 42, items: []))

    expect(output).to eq([ "━" * 60, "  Score: 42 / 100" ])
  end

  it "shows the gaps explanation, wrapped" do
    reporter.event(:explanation, text: "No FAQ content anywhere, and the description reads as marketing copy.")

    expect(output).to eq([
      "",
      "  Why: No FAQ content anywhere, and the description reads as",
      "  marketing copy."
    ])
  end

  it "flags a failed step with its reason" do
    reporter.event(:failure, step: "agent run", reason: "Gemini rate limited")

    expect(output).to eq([ "  ✗ agent run failed: Gemini rate limited" ])
  end

  it "prints any partial results underneath a failure, using the same human summaries" do
    r = reporter
    r.event(
      :failure, step: "agent run", reason: "Gemini rate limited",
      partial_results: { "get_product_data" => { title: "Cozy Wool Socks", variants: [] } }
    )

    expect(output).to eq([
      "  ✗ agent run failed: Gemini rate limited",
      "    Partial results before the failure:",
      %(      get_product_data → "Cozy Wool Socks" · 0 variants)
    ])
  end

  it "closes the box and prints the usage summary" do
    snapshot = GeoAudit::Usage::Tracker.new.tap do |tracker|
      tracker.record_call!(:agent)
      tracker.record_tokens(:agent, instance_double(LittleGhost::Usage, input_tokens: 14_200, output_tokens: 1_850))
    end.snapshot

    reporter.event(:usage_summary, snapshot: snapshot, elapsed: 23.0)

    expect(output).to eq([
      "━" * 60,
      "  1 Gemini calls · 14200 in / 1850 out tokens · 23.0s total"
    ])
  end

  it "silently ignores an unrecognized event name instead of raising" do
    expect { reporter.event(:something_new, foo: "bar") }.not_to raise_error
  end

  it "wraps every printed line in color codes when color is enabled" do
    r = reporter(color: true)

    r.event(:start, handle: "cozy-wool-socks", model: "gemini-flash-lite-latest")

    expect(io.string).to include("\e[")
  end

  it "prints plain text with no escape codes when color is disabled" do
    reporter.event(:start, handle: "cozy-wool-socks", model: "gemini-flash-lite-latest")

    expect(io.string).not_to include("\e[")
  end
end
