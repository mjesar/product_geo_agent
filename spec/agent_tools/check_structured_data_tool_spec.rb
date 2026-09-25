require "rails_helper"

RSpec.describe CheckStructuredDataTool do
  let(:structured_data_check) { instance_double(GeoAudit::StructuredDataCheck) }
  let(:tool) { described_class.new(structured_data_check: structured_data_check) }

  describe "#call" do
    it "delegates to StructuredDataCheck with the handle and returns its result" do
      allow(structured_data_check).to receive(:call).with("cozy-wool-socks").and_return(
        product_schema: true, faq_schema: false, schema_types_found: [ "Product" ]
      )

      result = tool.call({ "handle" => "cozy-wool-socks" })

      expect(result).to eq(product_schema: true, faq_schema: false, schema_types_found: [ "Product" ])
    end
  end
end
