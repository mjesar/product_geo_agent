require "rails_helper"

RSpec.describe CheckFaqPageTool do
  let(:faq_check) { instance_double(GeoAudit::FaqCheck) }
  let(:tool) { described_class.new(faq_check: faq_check) }

  describe "#call" do
    it "delegates to FaqCheck#page and returns its result" do
      allow(faq_check).to receive(:page).and_return(
        found: true, title: "Frequently Asked Questions", body: "<p>Answers here.</p>"
      )

      result = tool.call({})

      expect(result).to eq(found: true, title: "Frequently Asked Questions", body: "<p>Answers here.</p>")
    end
  end
end
