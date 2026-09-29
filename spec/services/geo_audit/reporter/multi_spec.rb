require "rails_helper"

RSpec.describe GeoAudit::Reporter::Multi do
  it "forwards the event to every reporter it holds" do
    first = instance_double(GeoAudit::Reporter::Null, event: nil)
    second = instance_double(GeoAudit::Reporter::Null, event: nil)

    described_class.new(first, second).event(:start, handle: "cozy-wool-socks", model: "gemini-flash-lite-latest")

    expect(first).to have_received(:event).with(:start, handle: "cozy-wool-socks", model: "gemini-flash-lite-latest")
    expect(second).to have_received(:event).with(:start, handle: "cozy-wool-socks", model: "gemini-flash-lite-latest")
  end

  it "does nothing when it holds no reporters" do
    expect { described_class.new.event(:start, handle: "cozy-wool-socks") }.not_to raise_error
  end
end
