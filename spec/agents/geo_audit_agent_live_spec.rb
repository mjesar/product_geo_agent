require "rails_helper"

RSpec.describe GeoAuditAgent, :live do
  it "runs a full audit against a real sandbox product with the real Gemini model" do
    pending "confirmed working against littleghostai/little_ghost#110 and #111 (both open), " \
            "but not yet in a released little_ghost gem — see Known limitations in CLAUDE.md"

    run = described_class.ask(
      "Audit the Shopify product with handle 'the-complete-snowboard' for AI discoverability."
    )

    expect(run).to be_completed
    expect(run.response).to be_present
  end
end
