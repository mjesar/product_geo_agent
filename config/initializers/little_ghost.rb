# frozen_string_literal: true

LittleGhost.configure do |config|
  config.providers = {
    gemini: {
      adapter: :gemini,
      api_key: ENV.fetch("GEMINI_API_KEY")
    }
  }
end
