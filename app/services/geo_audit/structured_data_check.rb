require "nokogiri"

module GeoAudit
  class StructuredDataCheck
    def initialize(password_auth: ShopifyStorefront::PasswordAuth.new)
      @password_auth = password_auth
    end

    def call(handle)
      response = @password_auth.authenticated_connection.get("products/#{handle}")
      types = schema_types(response.body)

      {
        product_schema: types.include?("Product"),
        faq_schema: types.include?("FAQPage"),
        schema_types_found: types
      }
    end

    private

    def schema_types(html)
      document = Nokogiri::HTML(html)

      document.css('script[type="application/ld+json"]').flat_map do |script|
        types_from(JSON.parse(script.text))
      rescue JSON::ParserError
        []
      end.uniq
    end

    def types_from(data)
      Array(data["@type"])
    end
  end
end
