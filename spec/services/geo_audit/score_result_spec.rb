require "rails_helper"

RSpec.describe GeoAudit::Score::Item do
  def build_item(weight:, points:)
    described_class.new(key: :x, label: "X", weight: weight, points: points, detail: "...")
  end

  describe "#lost" do
    it "returns weight minus points" do
      expect(build_item(weight: 15, points: 0).lost).to eq(15)
    end

    it "returns a whole number as an integer, not a float" do
      lost = build_item(weight: 10, points: 0.0).lost

      expect(lost).to eq(10)
      expect(lost).to be_an(Integer)
    end

    it "keeps a half point as a decimal" do
      expect(build_item(weight: 15, points: 7.5).lost).to eq(7.5)
    end

    it "rounds float noise from proportional credit to one decimal" do
      # alt text with 2 of 3 images: 10 * (2 / 3.0) = 6.666666666666667
      expect(build_item(weight: 10, points: 10 * (2 / 3.0)).lost).to eq(3.3)
    end

    it "returns zero for an item with full credit" do
      expect(build_item(weight: 15, points: 15).lost).to eq(0)
    end
  end
end

RSpec.describe GeoAudit::Score::Result do
  def build_item(key, weight:, points:)
    GeoAudit::Score::Item.new(key: key, label: key.to_s, weight: weight, points: points, detail: "...")
  end

  describe "#gaps" do
    it "leaves out items that earned full credit" do
      result = described_class.new(total: 15, items: [
        build_item(:full, weight: 10, points: 10),
        build_item(:partial, weight: 15, points: 7.5)
      ])

      expect(result.gaps.map(&:key)).to eq([ :partial ])
    end

    it "sorts the biggest loss first" do
      result = described_class.new(total: 10, items: [
        build_item(:small, weight: 10, points: 5),
        build_item(:huge, weight: 20, points: 0),
        build_item(:medium, weight: 15, points: 5)
      ])

      expect(result.gaps.map(&:key)).to eq([ :huge, :medium, :small ])
    end

    it "keeps equal losses in their original rubric order" do
      # Five items tied at 15 lost, in a known order, plus one bigger loss at the
      # end. A sort that isn't stable could shuffle the tied ones; this asserts
      # they come back exactly as they went in, after the bigger loss.
      result = described_class.new(total: 0, items: [
        build_item(:first, weight: 15, points: 0),
        build_item(:second, weight: 15, points: 0),
        build_item(:third, weight: 15, points: 0),
        build_item(:fourth, weight: 15, points: 0),
        build_item(:fifth, weight: 15, points: 0),
        build_item(:biggest, weight: 20, points: 0)
      ])

      expect(result.gaps.map(&:key)).to eq([ :biggest, :first, :second, :third, :fourth, :fifth ])
    end

    it "returns an empty list when every item earned full credit" do
      result = described_class.new(total: 100, items: [ build_item(:full, weight: 100, points: 100) ])

      expect(result.gaps).to eq([])
    end
  end

  describe "#total_lost" do
    it "is 100 minus the total" do
      expect(described_class.new(total: 85, items: []).total_lost).to eq(15)
    end

    it "adds up to 100 with the rounded total even when items lose half points" do
      # 77.5 of partial credit rounds to a total of 78; summing the items' losses
      # would give 22.5 and 78 + 22.5 would be 100.5.
      result = GeoAudit::Score.new(
        tool_results: {
          get_product_data: { images: [ "alt" ] },
          check_faq_page: { found: true },
          check_faq_metafield: { found: false },
          check_structured_data: { product_schema_complete: true },
          check_ai_citation: { mentioned: true }
        },
        ratings: {
          description_quality: { rating: "fair", reason: "r" },
          buyer_questions_answered: { rating: "fair", reason: "r" },
          specs_clarity: { rating: "fair", reason: "r" }
        }
      ).call

      expect(result.total).to eq(78)
      expect(result.total_lost).to eq(22)
      expect(result.total + result.total_lost).to eq(100)
    end
  end
end
