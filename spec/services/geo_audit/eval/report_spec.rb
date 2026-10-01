require "rails_helper"

RSpec.describe GeoAudit::Eval::Report do
  let(:expectation) do
    GeoAudit::Eval::Expectations.new(
      "products" => {
        "cozy-wool-socks" => {
          "ratings" => {
            "description_quality" => { "accept" => [ "poor" ], "expected" => "poor" },
            "buyer_questions_answered" => { "accept" => [ "poor", "fair" ], "expected" => "poor" },
            "specs_clarity" => { "accept" => [ "poor", "fair" ] }
          },
          "facts" => { "faq_source" => "metafield" },
          "tools" => { "must_call" => [ "check_faq_metafield" ] }
        }
      }
    ).fetch("cozy-wool-socks")
  end

  let(:good_ratings) do
    {
      "description_quality" => { "rating" => "poor", "reason" => "x" },
      "buyer_questions_answered" => { "rating" => "poor", "reason" => "x" },
      "specs_clarity" => { "rating" => "poor", "reason" => "x" }
    }
  end
  let(:good_tools) { { "check_faq_page" => { found: false }, "check_faq_metafield" => { found: true } } }

  def run(index, ratings: good_ratings, tool_results: good_tools, total: 30, error: nil)
    score = total && GeoAudit::Score::Result.new(total: total, items: [])
    GeoAudit::Eval::Runner::Run.new(index: index, ratings: error ? nil : ratings,
                                    tool_results: error ? nil : tool_results,
                                    score: error ? nil : score, calls: 7, error: error)
  end

  def rated(rating, item: "specs_clarity")
    good_ratings.merge(item => { "rating" => rating, "reason" => "x" })
  end

  def item(report, key)
    report.items.find { |i| i.key == key }
  end

  subject(:report) { described_class.new(expectation) }

  it "passes every item when every run matches" do
    result = report.call([ run(1), run(2), run(3) ])

    expect(result.handle).to eq("cozy-wool-socks")
    expect(result.completed).to eq(3)
    expect(result.items.map(&:verdict).uniq).to eq([ :pass ])
    expect(result).not_to be_failed
  end

  it "lists ratings, then facts, then tools" do
    result = report.call([ run(1) ])

    expect(result.items.map(&:kind)).to eq([ :rating, :rating, :rating, :fact, :tool ])
  end

  it "keeps what each run observed, in run order" do
    result = report.call([ run(1, ratings: rated("poor")), run(2, ratings: rated("fair")) ])

    expect(item(result, :specs_clarity).observed).to eq([ "poor", "fair" ])
  end

  describe "verdicts" do
    it "is fail when any run was outside the accepted set, even if the others passed" do
      result = report.call([ run(1), run(2, ratings: rated("good", item: "description_quality")), run(3) ])

      expect(item(result, :description_quality).verdict).to eq(:fail)
      expect(item(result, :description_quality).statuses).to eq([ :pass, :fail, :pass ])
      expect(result).to be_failed
    end

    it "is flaky when no run failed but the observed rating changed between runs" do
      result = report.call([ run(1, ratings: rated("poor")), run(2, ratings: rated("fair")), run(3) ])

      expect(item(result, :specs_clarity).verdict).to eq(:flaky)
      expect(result).not_to be_failed
    end

    it "is off-expectation when every run agrees but not with the predicted value" do
      result = report.call([ run(1, ratings: rated("fair", item: "buyer_questions_answered")),
                             run(2, ratings: rated("fair", item: "buyer_questions_answered")) ])

      expect(item(result, :buyer_questions_answered).verdict).to eq(:off_expectation)
      expect(result).not_to be_failed
    end

    it "is fail for a fact or tool that was never produced" do
      result = report.call([ run(1, tool_results: {}) ])

      expect(item(result, :faq_source)).to have_attributes(verdict: :fail, observed: [ nil ])
      expect(item(result, "check_faq_metafield").verdict).to eq(:fail)
    end

    it "counts verdicts" do
      result = report.call([ run(1, ratings: rated("poor")), run(2, ratings: rated("fair")) ])

      expect(result.verdict_counts).to eq(pass: 4, flaky: 1)
    end
  end

  describe "errored runs" do
    it "excludes them from the checks and keeps their messages" do
      result = report.call([ run(1), run(2, error: "Gemini rate limited"), run(3) ])

      expect(result.completed).to eq(2)
      expect(result.errors).to eq([ "Gemini rate limited" ])
      expect(item(result, :specs_clarity).observed.size).to eq(2)
    end

    it "fails the product when no run completed" do
      result = report.call([ run(1, error: "boom"), run(2, error: "boom") ])

      expect(result.completed).to eq(0)
      expect(result.items).to be_empty
      expect(result).to be_failed
    end
  end

  describe "scores" do
    it "collects each completed run's total and reports the median" do
      result = report.call([ run(1, total: 30), run(2, total: 45), run(3, total: 30) ])

      expect(result.scores).to eq([ 30, 45, 30 ])
      expect(result.median_score).to eq(30.0)
    end

    it "averages the two middle scores for an even count" do
      result = report.call([ run(1, total: 30), run(2, total: 40) ])

      expect(result.median_score).to eq(35.0)
    end

    it "has no median without completed runs" do
      expect(report.call([ run(1, error: "boom") ]).median_score).to be_nil
    end
  end
end
