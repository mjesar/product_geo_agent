require "rails_helper"

RSpec.describe GeoAuditAgent, :live do
  it "runs a full audit against a real sandbox product with the real Gemini model" do
    run = described_class.ask(
      "Audit the Shopify product with handle 'the-complete-snowboard' for AI discoverability."
    )

    expect(run).to be_completed
    expect(run.response).to be_present
  end
end
