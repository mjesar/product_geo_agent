require "rails_helper"

RSpec.describe GeoAudit::Models do
  describe ".for" do
    it "returns the configured model for a known role" do
      expect(described_class.for(:agent)).to eq("gemini:gemini-flash-lite-latest")
    end

    it "raises for an unknown role" do
      expect { described_class.for(:nonexistent) }.to raise_error(ArgumentError, /unknown model role/)
    end
  end
end
