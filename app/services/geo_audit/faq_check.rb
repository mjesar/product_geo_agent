module GeoAudit
  class FaqCheck
    def initialize(client: ShopifyStorefront::Client.new)
      @client = client
    end

    def page
      query = <<~GRAPHQL
        query CheckFaqPage {
          page(handle: "faq") {
            title
            body
          }
        }
      GRAPHQL

      data = @client.query(query)
      page = data["page"]

      { found: !page.nil?, title: page&.dig("title"), body: page&.dig("body") }
    end

    def metafield(handle)
      query = <<~GRAPHQL
        query CheckFaqMetafield($handle: String!) {
          product(handle: $handle) {
            metafield(namespace: "custom", key: "faq") {
              value
            }
          }
        }
      GRAPHQL

      data = @client.query(query, variables: { handle: handle })
      metafield = data.dig("product", "metafield")

      { found: !metafield.nil?, value: metafield&.dig("value") }
    end
  end
end
