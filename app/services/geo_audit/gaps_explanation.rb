require "erb"

module GeoAudit
  class GapsExplanation
    MODEL = "gemini:gemini-flash-lite-latest".freeze
    PROMPT_PATH = Rails.root.join("app/prompts/geo_audit/gaps_explanation.erb")

    def call(score:)
      prompt = ERB.new(File.read(PROMPT_PATH), trim_mode: "-").result(binding)

      response = LittleGhost.generate(
        model: MODEL,
        messages: [ { role: :user, content: prompt } ]
      )

      response.text
    end
  end
end
