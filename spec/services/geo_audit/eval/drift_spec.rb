require "rails_helper"

RSpec.describe GeoAudit::Eval::Drift do
  def item(kind, key, observed)
    GeoAudit::Eval::Report::ItemSummary.new(kind: kind, key: key, expected: nil, observed: observed,
                                            statuses: [], verdict: :pass)
  end

  def report(items:, scores: [ 25, 25, 25 ])
    GeoAudit::Eval::Report::ProductReport.new(handle: "cozy-wool-socks", completed: scores.size, errors: [],
                                              items: items, scores: scores)
  end

  let(:entry) do
    {
      "model" => "gemini:test", "git_sha" => "abc123", "recorded_at" => "20261001T000000Z",
      "scores" => [ 25, 25, 25 ],
      "items" => {
        "rating:specs_clarity" => [ "poor", "poor", "fair" ],
        "fact:alt_text" => [ { "with_alt" => 1, "of" => 1 } ],
        "fact:faq_source" => [ "metafield", "metafield", "page" ],
        "tool:check_faq_metafield" => [ "called", "called" ]
      }
    }
  end

  let(:unchanged_items) do
    [ item(:rating, :specs_clarity, [ "poor", "poor", "poor" ]),
      item(:fact, :alt_text, [ { with_alt: 1, of: 1 } ]),
      item(:fact, :faq_source, [ "metafield", "metafield", "metafield" ]),
      item(:tool, "check_faq_metafield", [ "called", "called" ]) ]
  end

  def drift(items: unchanged_items, scores: [ 25, 25, 25 ])
    described_class.new.call(entry, report(items: items, scores: scores))
  end

  it "reports no drift when the typical results are the same, even if single runs differ" do
    result = drift

    expect(result).not_to be_drifted
    expect(result.meta).to eq("model" => "gemini:test", "git_sha" => "abc123", "recorded_at" => "20261001T000000Z")
  end

  it "reports a rating whose typical value moved a full step" do
    items = unchanged_items.dup
    items[0] = item(:rating, :specs_clarity, [ "fair", "fair", "fair" ])

    expect(drift(items: items).changes).to eq(
      [ described_class::Change.new(key: "rating:specs_clarity", before: "poor", after: "fair") ]
    )
  end

  it "does not report one outlier among otherwise unchanged ratings" do
    items = unchanged_items.dup
    items[0] = item(:rating, :specs_clarity, [ "poor", "poor", "good" ])

    expect(drift(items: items)).not_to be_drifted
  end

  it "reports a fact or tool whose most common value changed" do
    items = unchanged_items.dup
    items[2] = item(:fact, :faq_source, [ "page", "page", "metafield" ])
    items[3] = item(:tool, "check_faq_metafield", [ "not called", "not called" ])

    expect(drift(items: items).changes.map(&:key)).to eq([ "fact:faq_source", "tool:check_faq_metafield" ])
  end

  it "compares nested facts across a JSON round trip" do
    items = unchanged_items.dup
    items[1] = item(:fact, :alt_text, [ { with_alt: 0, of: 1 } ])

    expect(drift(items: items).changes.map(&:key)).to eq([ "fact:alt_text" ])
  end

  it "reports a median score that moved by a full rating step or more" do
    result = drift(scores: [ 30, 30, 30 ])

    expect(result.changes).to eq([ described_class::Change.new(key: "score", before: 25.0, after: 30.0) ])
  end

  it "ignores a smaller score movement" do
    expect(drift(scores: [ 25, 27, 27 ])).not_to be_drifted
  end

  it "skips an item that had no baseline, since there is nothing to compare" do
    items = unchanged_items + [ item(:fact, :ai_citation, [ false ]) ]

    expect(drift(items: items)).not_to be_drifted
  end
end
