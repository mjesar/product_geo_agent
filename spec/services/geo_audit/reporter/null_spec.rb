require "rails_helper"

RSpec.describe GeoAudit::Reporter::Null do
  it "accepts any event without raising or producing output" do
    reporter = described_class.new

    expect {
      reporter.event(:start, handle: "cozy-wool-socks", model: "gemini-flash-lite-latest")
      reporter.event(:anything, foo: "bar")
    }.not_to raise_error
  end
end
