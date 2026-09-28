require "rails_helper"

RSpec.describe GeoAudit::RetryPolicy do
  def http_error(status)
    LittleGhost::Providers::HTTPError.new("boom", status: status, body: "{}")
  end

  describe ".delay_for" do
    it "backs off 5s, 15s, 30s for a 503, then stops" do
      error = http_error(503)

      expect(described_class.delay_for(error, attempt: 1)).to eq(5)
      expect(described_class.delay_for(error, attempt: 2)).to eq(15)
      expect(described_class.delay_for(error, attempt: 3)).to eq(30)
      expect(described_class.delay_for(error, attempt: 4)).to be_nil
    end

    it "backs off 15s, 30s, 60s for a 429, then stops" do
      error = http_error(429)

      expect(described_class.delay_for(error, attempt: 1)).to eq(15)
      expect(described_class.delay_for(error, attempt: 2)).to eq(30)
      expect(described_class.delay_for(error, attempt: 3)).to eq(60)
      expect(described_class.delay_for(error, attempt: 4)).to be_nil
    end

    it "does not retry other HTTP statuses" do
      expect(described_class.delay_for(http_error(400), attempt: 1)).to be_nil
    end

    it "does not retry errors that aren't provider HTTP errors" do
      expect(described_class.delay_for(StandardError.new("boom"), attempt: 1)).to be_nil
    end
  end
end
