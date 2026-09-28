module GeoAudit
  module Models
    BY_ROLE = {
      agent: "gemini:gemini-flash-lite-latest",
      citation: "gemini:gemini-flash-lite-latest",
      explanation: "gemini:gemini-flash-lite-latest",
      chat: "gemini:gemini-flash-lite-latest"
    }.freeze

    def self.for(role)
      BY_ROLE.fetch(role) { raise ArgumentError, "unknown model role: #{role.inspect}" }
    end
  end
end
