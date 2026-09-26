module GeoAudit
  class CitationCheck
    MODEL = "gemini:gemini-flash-lite-latest".freeze

    def call(product_title:, category:)
      question = "What's a good #{category} you'd recommend?"

      response = LittleGhost.generate(
        model: MODEL,
        messages: [ { role: :user, content: question } ]
      )

      mentioned = response.text.downcase.include?(product_title.downcase)

      { mentioned: mentioned, question: question, response: response.text }
    end
  end
end
