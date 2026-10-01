require "rails_helper"

RSpec.describe GeoAudit::Eval::Drift do
  def item(kind, key, observed)
    GeoAudit::Eval::Report::ItemSummary.new(kind: kind, key: key, expected: nil, observed: observed,
                                            statuses: [], verdict: :pass)
  end

  def report(items:, scores:)
    GeoAudit::Eval::Report::ProductReport.new(handle: "cozy-wool-socks", completed: scores.size, errors: [],
                                              items: items, scores: scores)
  end

  let(:entry) do
    {
      "model" => "gemini:test", "git_sha" => "abc123", "recorded_at" => "20261001T000000Z",
      "scores" => [ 25, 25, 25, 25, 25 ],
      "items" => {
        "rating:specs_clarity" => [ "poor", "poor", "poor", "poor", "fair" ],
        "fact:alt_text" => [ { "with_alt" => 1, "of" => 1 } ],
        "fact:faq_source" => [ "metafield", "metafield", "metafield", "metafield", "page" ],
        "tool:check_faq_metafield" => [ "called", "called" ]
      }
    }
  end

  let(:unchanged_items) do
    [ item(:rating, :specs_clarity, [ "poor", "poor", "poor", "poor", "poor" ]),
      item(:fact, :alt_text, [ { with_alt: 1, of: 1 } ]),
      item(:fact, :faq_source, [ "metafield", "metafield", "metafield", "metafield", "metafield" ]),
      item(:tool, "check_faq_metafield", [ "called", "called" ]) ]
  end

  def drift(items: unchanged_items, scores: [ 25, 25, 25, 25, 25 ], baseline: entry)
    described_class.new.call(baseline, report(items: items, scores: scores))
  end

  def replace(index, new_item)
    unchanged_items.dup.tap { |items| items[index] = new_item }
  end

  it "reports no drift when the typical results are the same, even if single runs differ" do
    result = drift

    expect(result).not_to be_drifted
    expect(result.unstable).to be_empty
    expect(result.meta).to eq("model" => "gemini:test", "git_sha" => "abc123", "recorded_at" => "20261001T000000Z")
  end

  it "reports a rating whose typical value moved a full step" do
    result = drift(items: replace(0, item(:rating, :specs_clarity, [ "fair", "fair", "fair", "fair", "fair" ])))

    expect(result.changes).to eq(
      [ described_class::Change.new(key: "rating:specs_clarity", before: "poor", after: "fair") ]
    )
  end

  it "does not report one outlier among otherwise unchanged ratings" do
    result = drift(items: replace(0, item(:rating, :specs_clarity, [ "poor", "poor", "poor", "poor", "good" ])))

    expect(result).not_to be_drifted
    expect(result.unstable).to be_empty
  end

  it "reports a fact or tool whose most common value changed" do
    items = replace(2, item(:fact, :faq_source, [ "page", "page", "page", "page", "metafield" ]))
    items[3] = item(:tool, "check_faq_metafield", [ "not called", "not called" ])

    expect(drift(items: items).changes.map(&:key)).to eq([ "fact:faq_source", "tool:check_faq_metafield" ])
  end

  it "compares nested facts across a JSON round trip" do
    result = drift(items: replace(1, item(:fact, :alt_text, [ { with_alt: 0, of: 1 } ])))

    expect(result.changes.map(&:key)).to eq([ "fact:alt_text" ])
  end

  it "reports a median score that moved by a full rating step or more" do
    result = drift(scores: [ 30, 30, 30, 30, 30 ])

    expect(result.changes).to eq([ described_class::Change.new(key: "score", before: 25.0, after: 30.0) ])
  end

  it "ignores a smaller score movement" do
    expect(drift(scores: [ 27, 27, 27, 27, 27 ])).not_to be_drifted
  end

  it "skips an item that had no baseline, since there is nothing to compare" do
    items = unchanged_items + [ item(:fact, :ai_citation, [ false ]) ]

    expect(drift(items: items)).not_to be_drifted
  end

  describe "unstable items" do
    let(:split) { [ "fair", "fair", "fair", "good", "good" ] }

    it "does not compare an item whose new runs split too evenly" do
      result = drift(items: replace(0, item(:rating, :specs_clarity, split)))

      expect(result.unstable).to eq([ "rating:specs_clarity" ])
      expect(result.changes).to be_empty
      expect(result).not_to be_drifted
    end

    it "does not compare an item whose baseline runs split too evenly" do
      baseline = entry.merge("items" => entry["items"].merge("rating:specs_clarity" => split))
      result = drift(items: replace(0, item(:rating, :specs_clarity, [ "good", "good", "good", "good", "good" ])),
                     baseline: baseline)

      expect(result.unstable).to eq([ "rating:specs_clarity" ])
      expect(result.changes).to be_empty
    end

    it "does not compare the score when its runs split too evenly" do
      result = drift(scores: [ 65, 65, 65, 70, 70 ])

      expect(result.unstable).to eq([ "score" ])
      expect(result.changes).to be_empty
    end

    it "treats four of five as stable and three of five as not" do
      four = drift(items: replace(0, item(:rating, :specs_clarity, [ "fair", "fair", "fair", "fair", "good" ])))
      three = drift(items: replace(0, item(:rating, :specs_clarity, [ "fair", "fair", "fair", "good", "good" ])))

      expect(four.unstable).to be_empty
      expect(three.unstable).to eq([ "rating:specs_clarity" ])
    end

    it "still reports real drift on the items that are stable" do
      items = replace(0, item(:rating, :specs_clarity, split))
      items[2] = item(:fact, :faq_source, [ "page", "page", "page", "page", "page" ])

      result = drift(items: items)

      expect(result.unstable).to eq([ "rating:specs_clarity" ])
      expect(result.changes.map(&:key)).to eq([ "fact:faq_source" ])
    end
  end
end
