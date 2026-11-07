module GeoAudit
  class Redactor
    ENV_KEYS = %w[GEMINI_API_KEY SHOPIFY_STOREFRONT_TOKEN SHOPIFY_STOREFRONT_PASSWORD].freeze
    NAME_PATTERN = /token|password|api_key|secret/i
    REPLACEMENT = "[REDACTED]"

    def initialize(secrets: ENV_KEYS.filter_map { |key| ENV[key] }.reject(&:empty?))
      @secrets = secrets
    end

    def redact(value)
      case value
      when String
        redact_string(value)
      when Hash
        value.to_h { |key, child| [ key, redact_by_name?(key, child) ? REPLACEMENT : redact(child) ] }
      when Array
        value.map { |item| redact(item) }
      else
        value
      end
    end

    private

    def redact_string(text)
      @secrets.reduce(text) { |result, secret| result.gsub(secret, REPLACEMENT) }
    end

    # Catches sensitive-looking fields even when the value isn't one of the known
    # ENV secrets above — e.g. a header or param we didn't think to enumerate.
    def redact_by_name?(key, value)
      return false if token_count?(key, value)

      key.to_s.match?(NAME_PATTERN)
    end

    # input_tokens and output_tokens are usage counts, not credentials. Only a number
    # qualifies, so a string under a name like access_tokens is still redacted.
    def token_count?(key, value)
      value.is_a?(Numeric) && key.to_s.match?(/_tokens\z/i)
    end
  end
end
