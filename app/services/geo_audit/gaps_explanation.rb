require "erb"

module GeoAudit
  class GapsExplanation
    MODEL = Models.for(:explanation)
    PROMPT_PATH = Rails.root.join("app/prompts/geo_audit/gaps_explanation.erb")

    def initialize(retrier: Retrier.new(tracker: Usage.current_tracker, part: :explanation))
      @retrier = retrier
    end

    def call(score:)
      prompt = ERB.new(File.read(PROMPT_PATH), trim_mode: "-").result(binding)

      response = @retrier.call do
        LittleGhost.generate(
          model: MODEL,
          messages: [ { role: :user, content: prompt } ]
        )
      end

      response.text
    end
  end
end
