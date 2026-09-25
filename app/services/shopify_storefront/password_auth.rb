require "faraday/cookie_jar"

module ShopifyStorefront
  class PasswordAuth
    class Error < StandardError; end

    def initialize(
      store_domain: ENV["SHOPIFY_STORE_DOMAIN"],
      password: ENV["SHOPIFY_STOREFRONT_PASSWORD"],
      connection: nil
    )
      @store_domain = store_domain
      @password = password
      @connection = connection
      @authenticated = false
    end

    # Returns a Faraday connection carrying the storefront password session,
    # ready for further GET requests against the store. A no-op on stores
    # that aren't password protected — see authenticate!.
    def authenticated_connection
      authenticate! unless @authenticated
      connection
    end

    private

    def authenticate!
      token = fetch_authenticity_token
      @authenticated = true and return unless token

      response = connection.post("password") do |req|
        req.headers["Content-Type"] = "application/x-www-form-urlencoded"
        req.body = URI.encode_www_form(authenticity_token: token, password: @password)
      end

      unless response.status == 302
        raise Error, "Storefront password login failed for #{@store_domain}"
      end

      @authenticated = true
    end

    # The password page embeds a Rails CSRF token tied to the session cookie
    # set on this same GET — without it, Shopify silently rejects any
    # password POST as incorrect, regardless of the actual password.
    def fetch_authenticity_token
      response = connection.get("password")
      response.body[/name="authenticity_token" value="([^"]+)"/, 1]
    end

    def connection
      @connection ||= Faraday.new(url: "https://#{@store_domain}/") do |builder|
        builder.use :cookie_jar
        builder.adapter Faraday.default_adapter
      end
    end
  end
end
