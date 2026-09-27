require "rails_helper"

RSpec.describe GeoAudit::Auditor, :live do
  it "runs a full scored audit against a real sandbox product with the real Gemini model" do
    result = described_class.new.call(handle: "the-complete-snowboard")

    expect(result.run).to be_completed
    expect(result.score.items.size).to eq(7)
    expect(result.score.total).to be_between(0, 100)
    expect(result.explanation).to be_present
  end
end
