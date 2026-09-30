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

  def http_error(status)
    LittleGhost::Providers::HTTPError.new("boom", status: status, body: "{}")
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

    def sent_prompt
      prompt = nil
      expect(LittleGhost).to have_received(:generate) { |messages:, **| prompt = messages.first[:content] }
      prompt
    end

    it "renders the total score, total points lost, and each gap into the prompt it sends" do
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
              "Total points lost: 15",
              "AI citation check: lost 15 of 15 points. AI assistant did not mention this product"
            )
          }
        ]
      )
    end

    it "lists gaps biggest loss first and leaves out items with full credit" do
      stub_gemini_response("...")

      score = build_score(total: 60, items: [
        build_item(key: :alt_text, label: "Alt text", weight: 10, points: 10, detail: "all have alt text"),
        build_item(key: :faq, label: "FAQ content", weight: 15, points: 0, detail: "no FAQ"),
        build_item(key: :buyer, label: "Buyer questions", weight: 20, points: 0, detail: "none answered"),
        build_item(key: :description, label: "Description", weight: 15, points: 7.5, detail: "thin")
      ])

      described_class.new.call(score: score)

      prompt = sent_prompt
      expect(prompt).not_to include("Alt text")
      expect(prompt.index("Buyer questions")).to be < prompt.index("FAQ content")
      expect(prompt.index("FAQ content")).to be < prompt.index("Description: lost 7.5 of 15 points")
    end

    it "says there are no gaps when every item earned full credit" do
      stub_gemini_response("...")

      score = build_score(total: 100, items: [
        build_item(key: :alt_text, label: "Alt text", weight: 10, points: 10, detail: "all have alt text")
      ])

      described_class.new.call(score: score)

      expect(sent_prompt).to include("Every item earned full credit, so there are no gaps to report.")
    end

    it "caps the gaps covered at three" do
      stub_gemini_response("...")

      described_class.new.call(score: build_score(total: 62))

      expect(sent_prompt).to match(/at most the top 3 gaps/)
      expect(sent_prompt).to match(/Do not mention any gap outside those\s+top 3/)
    end

    it "limits the hard-to-fix exception to the top three gaps, so it can't reopen the cap" do
      stub_gemini_response("...")

      described_class.new.call(score: build_score(total: 62))

      expect(sent_prompt).to match(/If one of those top 3 is hard for the owner to fix/)
    end

    it "asks for plain text with no markdown" do
      stub_gemini_response("...")

      described_class.new.call(score: build_score(total: 62))

      expect(sent_prompt).to match(/plain text only: no markdown, no bold, no asterisks/)
    end

    it "tells the model not to repeat the rating words in its prose" do
      stub_gemini_response("...")

      described_class.new.call(score: build_score(total: 62))

      expect(sent_prompt).to match(/Do not repeat the phrases "rated poor",\s+"rated fair", or "rated good"/)
    end

    it "tells the model to copy numbers exactly and never add or subtract them" do
      stub_gemini_response("...")

      described_class.new.call(score: build_score(total: 62))

      expect(sent_prompt).to match(/copied exactly from the lines above/)
      expect(sent_prompt).to match(/Never add,\s+subtract, or combine/)
    end

    it "tells the model never to recalculate the score" do
      stub_gemini_response("...")

      described_class.new.call(score: build_score(total: 100))

      expect(LittleGhost).to have_received(:generate).with(
        hash_including(messages: [ hash_including(content: a_string_including("never recalculate it")) ])
      )
    end

    it "retries a transient provider error before giving up" do
      retrier = GeoAudit::Retrier.new(sleeper: ->(_seconds) { })
      gaps_explanation = described_class.new(retrier: retrier)
      response = instance_double(LittleGhost::RunResult, text: "Add a FAQ page.")
      attempts = 0
      allow(LittleGhost).to receive(:generate) do
        attempts += 1
        attempts == 1 ? raise(http_error(503)) : response
      end

      result = gaps_explanation.call(score: build_score(total: 62))

      expect(result).to eq("Add a FAQ page.")
      expect(attempts).to eq(2)
    end
  end
end
