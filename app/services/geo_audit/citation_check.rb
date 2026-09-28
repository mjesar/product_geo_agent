module GeoAudit
  class CitationCheck
    MODEL = Models.for(:citation)

    def initialize(retrier: Retrier.new(tracker: Usage.current_tracker, part: :citation))
      @retrier = retrier
    end

    def call(product_title:, category:)
      question = "What's a good #{category} you'd recommend?"

      response = @retrier.call do
        LittleGhost.generate(
          model: MODEL,
          messages: [ { role: :user, content: question } ]
        )
      end

      mentioned = response.text.downcase.include?(product_title.downcase)

      { mentioned: mentioned, question: question, response: response.text }
    end
  end
end
