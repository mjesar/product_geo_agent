module GeoAudit
  # Cheap "does this handle resolve?" check Auditor runs before spending any Gemini
  # calls on an audit. One Storefront query, no model involved.
  class ProductLookup
    QUERY = <<~GRAPHQL
      query ProductExists($handle: String!) {
        product(handle: $handle) { id }
      }
    GRAPHQL

    def initialize(client: ShopifyStorefront::Client.new)
      @client = client
    end

    def exists?(handle)
      !@client.query(QUERY, variables: { handle: handle })["product"].nil?
    end
  end
end
