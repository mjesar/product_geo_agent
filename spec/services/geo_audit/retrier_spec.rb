require "rails_helper"

RSpec.describe GeoAudit::Retrier do
  def http_error(status)
    LittleGhost::Providers::HTTPError.new("boom", status: status, body: "{}")
  end

  let(:sleeps) { [] }
  let(:sleeper) { ->(seconds) { sleeps << seconds } }
  let(:retrier) { described_class.new(sleeper: sleeper) }

  it "returns the block's value when it succeeds on the first attempt" do
    result = retrier.call { "ok" }

    expect(result).to eq("ok")
    expect(sleeps).to eq([])
  end

  it "retries a retryable error until the block succeeds, sleeping the policy's delay each time" do
    attempts = 0
    result = retrier.call do
      attempts += 1
      raise http_error(503) if attempts < 3

      "ok"
    end

    expect(result).to eq("ok")
    expect(attempts).to eq(3)
    expect(sleeps).to eq([5, 15])
  end

  it "re-raises immediately without sleeping when the error isn't retryable" do
    expect { retrier.call { raise http_error(400) } }.to raise_error(LittleGhost::Providers::HTTPError)
    expect(sleeps).to eq([])
  end

  it "re-raises once the policy runs out of delays" do
    attempts = 0
    expect do
      retrier.call do
        attempts += 1
        raise http_error(503)
      end
    end.to raise_error(LittleGhost::Providers::HTTPError)

    expect(attempts).to eq(4)
    expect(sleeps).to eq([5, 15, 30])
  end
end
