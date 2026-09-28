require "rails_helper"

RSpec.describe GeoAudit::Usage::Tracker do
  def usage(input_tokens:, output_tokens:)
    instance_double(LittleGhost::Usage, input_tokens: input_tokens, output_tokens: output_tokens)
  end

  it "starts every part at zero" do
    snapshot = described_class.new.snapshot

    %i[agent citation explanation].each do |part|
      part_snapshot = snapshot.public_send(part)
      expect(part_snapshot.calls).to eq(0)
      expect(part_snapshot.retries).to eq(0)
      expect(part_snapshot.input_tokens).to eq(0)
      expect(part_snapshot.output_tokens).to eq(0)
    end
  end

  it "tracks calls, retries, and tokens per part independently" do
    tracker = described_class.new

    tracker.record_call!(:agent)
    tracker.record_call!(:agent)
    tracker.record_retry!(:agent)
    tracker.record_tokens(:agent, usage(input_tokens: 100, output_tokens: 20))

    tracker.record_call!(:citation)
    tracker.record_tokens(:citation, usage(input_tokens: 10, output_tokens: 5))

    snapshot = tracker.snapshot

    expect(snapshot.agent).to eq(GeoAudit::Usage::PartSnapshot.new(calls: 2, retries: 1, input_tokens: 100, output_tokens: 20))
    expect(snapshot.citation).to eq(GeoAudit::Usage::PartSnapshot.new(calls: 1, retries: 0, input_tokens: 10, output_tokens: 5))
    expect(snapshot.explanation).to eq(GeoAudit::Usage::PartSnapshot.new(calls: 0, retries: 0, input_tokens: 0, output_tokens: 0))
  end

  it "sums every part into the total" do
    tracker = described_class.new
    tracker.record_call!(:agent)
    tracker.record_tokens(:agent, usage(input_tokens: 100, output_tokens: 20))
    tracker.record_call!(:citation)
    tracker.record_retry!(:citation)
    tracker.record_tokens(:citation, usage(input_tokens: 10, output_tokens: 5))
    tracker.record_call!(:explanation)
    tracker.record_tokens(:explanation, usage(input_tokens: 50, output_tokens: 15))

    total = tracker.snapshot.total

    expect(total).to eq(GeoAudit::Usage::PartSnapshot.new(calls: 3, retries: 1, input_tokens: 160, output_tokens: 40))
  end

  it "raises for an unknown part" do
    tracker = described_class.new

    expect { tracker.record_call!(:nonexistent) }.to raise_error(KeyError)
  end
end
