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

    [ GeoAudit::StructuredDataCheck::Error, ShopifyStorefront::PasswordAuth::Error ].each do |error_class|
      it "turns #{error_class} into a ToolError the model can read" do
        allow(structured_data_check).to receive(:call).and_raise(error_class, "returned HTTP 503")

        expect { tool.call({ "handle" => "cozy-wool-socks" }) }
          .to raise_error(LittleGhost::ToolError, "returned HTTP 503")
      end
    end
  end

  describe "#execute" do
    it "returns an error result carrying the message, the shape ToolResultCollector receives" do
      allow(structured_data_check).to receive(:call)
        .and_raise(GeoAudit::StructuredDataCheck::Error, "returned HTTP 503")

      result = tool.execute({ "handle" => "cozy-wool-socks" })

      expect(result.status).to eq(:error)
      expect(result.value).to eq("returned HTTP 503")
    end
  end
end
