require "nokogiri"

module GeoAudit
  class StructuredDataCheck
    class Error < StandardError; end

    def initialize(password_auth: ShopifyStorefront::PasswordAuth.new)
      @password_auth = password_auth
    end

    def call(handle)
      response = @password_auth.authenticated_connection.get(product_path(handle))

      # An error page has no JSON-LD either, so without this check a 503 would
      # look exactly like a product with no structured data and lose its points.
      raise Error, "Product page for #{handle} returned HTTP #{response.status}" unless response.success?

      nodes = schema_nodes(response.body)
      types = nodes.flat_map { |node| Array(node["@type"]) }.uniq

      {
        product_schema: types.include?("Product"),
        # Shopify themes emit a Product block for every product, even one with
        # an empty description, so its mere presence proves nothing. It only
        # helps an AI assistant if it actually carries a description and offers.
        product_schema_complete: nodes.any? { |node| complete_product?(node) },
        faq_schema: types.include?("FAQPage"),
        schema_types_found: types
      }
    end

    private

    # The model picks this handle, and store text it has read could influence it.
    # Encoding keeps a value like "../admin" inside the products path. Dots aren't
    # encoded, so a handle made only of dots has to be rejected separately.
    def product_path(handle)
      raise Error, "Invalid product handle: #{handle.inspect}" if handle.delete(".").empty?

      "products/#{URI.encode_uri_component(handle)}"
    end

    def schema_nodes(html)
      document = Nokogiri::HTML(html)

      document.css('script[type="application/ld+json"]').flat_map do |script|
        nodes_from(JSON.parse(script.text))
      rescue JSON::ParserError
        []
      end
    end

    # JSON-LD isn't always one object: themes and apps also emit a top-level
    # array, or wrap several entities in an "@graph" list. Flatten all of those
    # into one list of entity hashes.
    def nodes_from(data)
      case data
      when Array then data.flat_map { |item| nodes_from(item) }
      when Hash then [ data ] + nodes_from(data["@graph"])
      else []
      end
    end

    def complete_product?(node)
      Array(node["@type"]).include?("Product") &&
        node["description"].to_s.strip.present? &&
        node["offers"].present?
    end
  end
end
