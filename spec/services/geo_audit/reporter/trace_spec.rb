require "rails_helper"

RSpec.describe GeoAudit::Reporter::Trace do
  def lines_at(path)
    File.readlines(path).map { |line| JSON.parse(line) }
  end

  it "creates the trace directory and file if they don't exist yet" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "nested", "run.jsonl")
      trace = described_class.new(path: path, clock: -> { Time.utc(2026, 9, 29, 12, 0, 0) })

      trace.event(:start, handle: "cozy-wool-socks", model: "gemini-flash-lite-latest")

      expect(File).to exist(path)
    end
  end

  it "writes one JSON line per event, with a timestamp, the event name, and its data" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "run.jsonl")
      trace = described_class.new(path: path, clock: -> { Time.utc(2026, 9, 29, 12, 0, 0) })

      trace.event(:start, handle: "cozy-wool-socks", model: "gemini-flash-lite-latest")
      trace.event(:tool_finished, name: "get_product_data", duration: 0.4, summary: "3 variants")

      entries = lines_at(path)
      expect(entries.length).to eq(2)
      expect(entries[0]).to eq(
        "at" => "2026-09-29T12:00:00.000Z", "event" => "start",
        "data" => { "handle" => "cozy-wool-socks", "model" => "gemini-flash-lite-latest" }
      )
      expect(entries[1]["event"]).to eq("tool_finished")
      expect(entries[1]["data"]).to eq("name" => "get_product_data", "duration" => 0.4, "summary" => "3 variants")
    end
  end

  it "flattens a Data.define value (and its nested Data values) into plain JSON" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "run.jsonl")
      trace = described_class.new(path: path)
      score = GeoAudit::Score::Result.new(
        total: 42,
        items: [ GeoAudit::Score::Item.new(key: :faq_content, label: "FAQ content", weight: 15, points: 15, detail: "Found") ]
      )

      trace.event(:score_computed, result: score)

      expect(lines_at(path).first["data"]).to eq(
        "result" => {
          "total" => 42,
          "items" => [
            { "key" => "faq_content", "label" => "FAQ content", "weight" => 15, "points" => 15, "detail" => "Found" }
          ]
        }
      )
    end
  end

  it "redacts secrets before writing, the same as Terminal does" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "run.jsonl")
      redactor = GeoAudit::Redactor.new(secrets: [ "super-secret-token" ])
      trace = described_class.new(path: path, redactor: redactor)

      trace.event(:retry, part: :agent, attempt: 1, delay: 5, status: 429, reason: "super-secret-token")

      raw = File.read(path)
      expect(raw).not_to include("super-secret-token")
      expect(raw).to include("[REDACTED]")
    end
  end

  it "appends across multiple events instead of overwriting" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "run.jsonl")
      trace = described_class.new(path: path)

      trace.event(:start, handle: "cozy-wool-socks", model: "gemini-flash-lite-latest")
      trace.event(:usage_summary, snapshot: {}, elapsed: 1.0)

      expect(lines_at(path).map { |entry| entry["event"] }).to eq([ "start", "usage_summary" ])
    end
  end
end
