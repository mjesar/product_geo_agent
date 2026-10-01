require "rails_helper"

RSpec.describe GeoAudit::Eval::Baseline do
  let(:path) { Rails.root.join("tmp", "baseline_spec.json").to_s }
  let(:items) do
    [ GeoAudit::Eval::Report::ItemSummary.new(kind: :rating, key: :specs_clarity, expected: nil,
                                              observed: [ "poor", "fair" ], statuses: [ :pass, :pass ], verdict: :flaky),
      GeoAudit::Eval::Report::ItemSummary.new(kind: :fact, key: :alt_text, expected: nil,
                                              observed: [ { with_alt: 1, of: 1 } ], statuses: [ :pass ], verdict: :pass) ]
  end
  let(:report) do
    GeoAudit::Eval::Report::ProductReport.new(handle: "cozy-wool-socks", completed: 2, errors: [],
                                              items: items, scores: [ 25, 30 ])
  end

  subject(:baseline) { described_class.new(path) }

  after { FileUtils.rm_f(path) }

  def save(report, at: "20261001T000000Z")
    baseline.save(report, model: "gemini:test", git_sha: "abc123", at: at)
  end

  it "has no entry before anything was saved, and no file to read" do
    expect(baseline.entry_for("cozy-wool-socks")).to be_nil
  end

  it "saves what each check observed and each run's score, with where it came from" do
    save(report)

    expect(baseline.entry_for("cozy-wool-socks")).to eq(
      "recorded_at" => "20261001T000000Z", "model" => "gemini:test", "git_sha" => "abc123",
      "scores" => [ 25, 30 ],
      "items" => { "rating:specs_clarity" => [ "poor", "fair" ], "fact:alt_text" => [ { "with_alt" => 1, "of" => 1 } ] }
    )
  end

  it "keeps other products when one is saved, and replaces a product that is saved again" do
    other = report.with(handle: "other-socks")
    save(report)
    save(other)
    save(report, at: "20261002T000000Z")

    expect(baseline.entry_for("other-socks")).to be_present
    expect(baseline.entry_for("cozy-wool-socks")["recorded_at"]).to eq("20261002T000000Z")
  end
end
