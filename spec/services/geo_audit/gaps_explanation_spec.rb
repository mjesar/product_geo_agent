require "rails_helper"

RSpec.describe GeoAudit::GapsExplanation do
  def stub_gemini_response(text)
    response = instance_double(LittleGhost::RunResult, text: text)
    allow(LittleGhost).to receive(:generate).and_return(response)
    response
  end

  def build_score(total:, items: [])
    GeoAudit::Score::Result.new(total: total, items: items)
  end

  def build_item(key:, label:, weight:, points:, detail:)
    GeoAudit::Score::Item.new(key: key, label: label, weight: weight, points: points, detail: detail)
  end

  describe "#call" do
    it "returns the model's explanation text" do
      stub_gemini_response("Add a FAQ page and alt text on your product images to close the biggest gaps.")

      result = described_class.new.call(score: build_score(total: 62))

      expect(result).to eq("Add a FAQ page and alt text on your product images to close the biggest gaps.")
    end

    it "renders the total score and each item's breakdown into the prompt it sends" do
      stub_gemini_response("...")

      score = build_score(total: 85, items: [
        build_item(
          key: :ai_citation, label: "AI citation check", weight: 15, points: 0,
          detail: "AI assistant did not mention this product"
        )
      ])

      described_class.new.call(score: score)

      expect(LittleGhost).to have_received(:generate).with(
        model: GeoAudit::GapsExplanation::MODEL,
        messages: [
          {
            role: :user,
            content: a_string_including(
              "Total score: 85 / 100",
              "AI citation check (0/15 points): AI assistant did not mention this product"
            )
          }
        ]
      )
    end

    it "tells the model never to recalculate the score" do
      stub_gemini_response("...")

      described_class.new.call(score: build_score(total: 100))

      expect(LittleGhost).to have_received(:generate).with(
        hash_including(messages: [ hash_including(content: a_string_including("never recalculate it")) ])
      )
    end
  end
end
