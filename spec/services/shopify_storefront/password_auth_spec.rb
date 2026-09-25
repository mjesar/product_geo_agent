require "rails_helper"

RSpec.describe ShopifyStorefront::PasswordAuth do
  let(:store_domain) { "test-store.myshopify.com" }
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:test_connection) do
    Faraday.new(url: "https://#{store_domain}/") do |builder|
      builder.adapter :test, stubs
    end
  end
  let(:auth) do
    described_class.new(store_domain: store_domain, password: "correct-password", connection: test_connection)
  end

  describe "#authenticated_connection" do
    context "when the store is password protected and the password is correct" do
      it "logs in and returns the connection" do
        stubs.get("/password") do
          [ 200, {}, '<input type="hidden" name="authenticity_token" value="tok123" />' ]
        end
        stubs.post("/password") do |env|
          expect(env.request_headers["Content-Type"]).to eq("application/x-www-form-urlencoded")
          body = Rack::Utils.parse_nested_query(env.body)
          expect(body["authenticity_token"]).to eq("tok123")
          expect(body["password"]).to eq("correct-password")

          [ 302, { "Location" => "https://#{store_domain}/" }, "" ]
        end

        expect(auth.authenticated_connection).to eq(test_connection)
        stubs.verify_stubbed_calls
      end
    end

    context "when the store is password protected and the password is rejected" do
      it "raises a PasswordAuth::Error" do
        stubs.get("/password") do
          [ 200, {}, '<input type="hidden" name="authenticity_token" value="tok123" />' ]
        end
        stubs.post("/password") do
          [ 200, {}, "Password incorrect, please try again." ]
        end

        expect { auth.authenticated_connection }
          .to raise_error(ShopifyStorefront::PasswordAuth::Error, /test-store.myshopify.com/)
      end
    end

    context "when the store is not password protected" do
      it "does not attempt a login" do
        stubs.get("/password") do
          [ 200, {}, "<html>no password form here</html>" ]
        end

        expect(auth.authenticated_connection).to eq(test_connection)
        stubs.verify_stubbed_calls
      end
    end
  end
end
