require "rails_helper"

RSpec.describe GeoAudit::Eval::ReportFormatter do
  let(:expectation) do
    GeoAudit::Eval::Expectations.new(
      "products" => {
        "cozy-wool-socks" => {
          "ratings" => {
            "description_quality" => { "accept" => [ "poor" ], "expected" => "poor" },
            "buyer_questions_answered" => { "accept" => [ "poor", "fair" ] },
            "specs_clarity" => { "accept" => [ "poor", "fair" ], "expected" => "poor" }
          },
          "facts" => { "alt_text" => { "with_alt" => 1, "of" => 1 }, "faq_source" => "metafield" }
        }
      }
    ).fetch("cozy-wool-socks")
  end

  def ratings(description: "poor", specs: "poor")
    {
      "description_quality" => { "rating" => description, "reason" => "x" },
      "buyer_questions_answered" => { "rating" => "poor", "reason" => "x" },
      "specs_clarity" => { "rating" => specs, "reason" => "x" }
    }
  end

  let(:tools) do
    { "get_product_data" => { images: [ "alt" ] }, "check_faq_page" => { found: false },
      "check_faq_metafield" => { found: true } }
  end

  def run(index, total: 30, **rating_options)
    GeoAudit::Eval::Runner::Run.new(
      index: index, ratings: ratings(**rating_options), tool_results: tools,
      score: GeoAudit::Score::Result.new(total: total, items: []), calls: 7, error: nil
    )
  end

  def format_runs(runs)
    report = GeoAudit::Eval::Report.new(expectation).call(runs)
    described_class.new(report).call
  end

  it "heads the report with the handle and how many runs completed" do
    expect(format_runs([ run(1), run(2) ])).to start_with("cozy-wool-socks: 2 completed run(s)")
  end

  it "shows the score spread" do
    text = format_runs([ run(1, total: 30), run(2, total: 40), run(3, total: 35) ])

    expect(text).to include("score  min 30  median 35  max 40")
  end

  it "shows what each check expected and what the runs observed" do
    text = format_runs([ run(1), run(2, specs: "fair") ])

    expect(text).to match(/FLAKY rating\s+specs_clarity\s+expected poor or fair \(expect poor\)\s+observed fair x1, poor x1/)
    expect(text).to match(/PASS\s+rating\s+description_quality\s+expected poor\s{2,}observed poor x2/)
    expect(text).to match(/PASS\s+fact\s+alt_text\s+expected 1 of 1 with alt\s+observed 1 of 1 with alt x2/)
    expect(text).to match(/PASS\s+fact\s+faq_source\s+expected metafield\s+observed metafield x2/)
  end

  it "labels a failing item and fails the result" do
    text = format_runs([ run(1, description: "fair") ])

    expect(text).to match(/FAIL\s+rating\s+description_quality/)
    expect(text).to include("RESULT: FAIL (")
  end

  it "reports not observed when the evidence was never produced" do
    run = GeoAudit::Eval::Runner::Run.new(
      index: 1, ratings: ratings, tool_results: {},
      score: GeoAudit::Score::Result.new(total: 0, items: []), calls: 7, error: nil
    )

    expect(format_runs([ run ])).to match(/alt_text.*observed not observed x1/)
  end

  it "lists errored runs and counts them in the header" do
    errored = GeoAudit::Eval::Runner::Run.new(index: 2, ratings: nil, tool_results: nil, score: nil, calls: 8,
                                              error: "Gemini rate limited")
    text = format_runs([ run(1), errored ])

    expect(text).to include("1 completed run(s), 1 errored")
    expect(text).to include("error: Gemini rate limited")
  end

  describe "drift section" do
    let(:meta) { { "model" => "gemini:test", "git_sha" => "abc123", "recorded_at" => "20261001T000000Z" } }

    def with_drift(changes, unstable: [])
      report = GeoAudit::Eval::Report.new(expectation).call([ run(1), run(2) ])
      drift = GeoAudit::Eval::Drift::Result.new(meta: meta, changes: changes, unstable: unstable)
      described_class.new(report, drift: drift).call
    end

    it "lists what moved against the baseline, and says where the baseline came from" do
      change = GeoAudit::Eval::Drift::Change.new(key: "rating:specs_clarity", before: "poor", after: "fair")
      score = GeoAudit::Eval::Drift::Change.new(key: "score", before: 25.0, after: 30.0)
      text = with_drift([ change, score ])

      expect(text).to include("drift vs baseline (gemini:test, abc123, 20261001T000000Z):")
      expect(text).to include("  rating:specs_clarity: poor -> fair")
      expect(text).to include("  score: 25 -> 30")
    end

    it "says none when nothing moved, and does not change the result" do
      text = with_drift([])

      expect(text).to include("drift vs baseline")
      expect(text).to match(/drift vs baseline.*\n  none/)
      expect(text).to include("RESULT: PASS")
    end

    it "names the items that were not compared because their runs split too evenly" do
      text = with_drift([], unstable: [ "rating:specs_clarity", "score" ])

      expect(text).to include("  none")
      expect(text).to include("not compared (unstable, runs split too evenly): rating:specs_clarity, score")
    end

    it "shows no drift section when there is no baseline" do
      expect(format_runs([ run(1) ])).not_to include("drift vs baseline")
    end
  end

  it "passes when every item passes" do
    expect(format_runs([ run(1), run(2) ])).to include("RESULT: PASS")
  end
end
