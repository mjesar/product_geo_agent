class GetProductDataTool < LittleGhost::Tool
  tool_name "get_product_data"
  description "Fetches a Shopify product's core data by handle: title, description, " \
              "images with alt text, variants, and SEO fields. Always call this first " \
              "— the description's length and quality determine how deep the remaining " \
              "checks (FAQ content, structured data, AI citation) need to go."

  input_schema type: "object", properties: { handle: { type: "string" } }, required: [ "handle" ], additionalProperties: false

  def initialize(client: ShopifyStorefront::Client.new, **kwargs)
    @client = client
    super(**kwargs)
  end

  def call(input)
    query = <<~GRAPHQL
     query GetProduct($handle: String!) {
        product(handle: $handle) {
          title
          description
          images(first: 10) {
            edges { node { altText } }
          }
          variants(first: 10) {
            edges { node { title price { amount currencyCode } } }
          }
          seo {
            title
            description
          }
        }
      }
    GRAPHQL

    handle = input.fetch("handle")
    data = fetch(query, handle)
    product = data["product"]

    raise LittleGhost::ToolError, "product not found for handle #{handle}" if product.nil?

    {
      title: product["title"],
      description: product["description"],
      images: product["images"]["edges"].map { |edge| edge["node"]["altText"] },
      variants: product["variants"]["edges"].map { |edge| variant(edge["node"]) },
      seo: product["seo"]
    }
  end

  private

  def fetch(query, handle)
    @client.query(query, variables: { handle: handle })
  rescue ShopifyStorefront::Client::Error => error
    raise LittleGhost::ToolError, "Could not fetch product data for #{handle}: #{error.message}"
  end

  def variant(node)
    { title: node["title"], price: { amount: node["price"]["amount"], currency_code: node["price"]["currencyCode"] } }
  end
end
