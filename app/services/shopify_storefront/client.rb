module ShopifyStorefront
  class Client
    class Error < StandardError; end

    API_VERSION = "2026-07"

    def initialize(
      store_domain: ENV["SHOPIFY_STORE_DOMAIN"],
      token: ENV["SHOPIFY_STOREFRONT_TOKEN"],
      connection: nil
    )
      @store_domain = store_domain
      @token = token
      @connection = connection
    end

    def query(query_string, variables: {})
      response = connection.post("graphql.json") do |req|
        req.headers["Content-Type"] = "application/json"
        req.headers["X-Shopify-Storefront-Access-Token"] = @token
        req.body = { query: query_string, variables: variables }.to_json
      end

      unless response.success?
        raise Error, "Storefront API request failed: #{response.status} #{response.body}"
      end

      body = JSON.parse(response.body)

      if body["errors"].present?
        messages = body["errors"].map { |e| e["message"] }.join(", ")
        raise Error, "Storefront API returned errors: #{messages}"
      end

      body["data"]
    end

    private

    def connection
      @connection ||= Faraday.new(url: "https://#{@store_domain}/api/#{API_VERSION}/")
    end
  end
end
