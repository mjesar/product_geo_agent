require "rails_helper"

RSpec.describe GeoAudit::CurrentAudit do
  after { described_class.current = nil }

  def build
    described_class.new(tracker: GeoAudit::Usage::Tracker.new, reporter: GeoAudit::Reporter::Null.new)
  end

  describe "#record_tool_result" do
    it "stores each tool's result by name, for reading back even after a failed run" do
      current_audit = build

      current_audit.record_tool_result("get_product_data", { title: "Cozy Wool Socks" })

      expect(current_audit.tool_results).to eq("get_product_data" => { title: "Cozy Wool Socks" })
    end

    it "clears an earlier failure for the same tool, so a retry that worked doesn't count against the audit" do
      current_audit = build
      current_audit.record_tool_failure("check_structured_data", "HTTP 503")

      current_audit.record_tool_result("check_structured_data", { product_schema: true })

      expect(current_audit.tool_failures).to be_empty
    end
  end

  describe "#record_tool_failure" do
    it "stores the reason by tool name and leaves other tools' results alone" do
      current_audit = build
      current_audit.record_tool_result("get_product_data", { title: "Cozy Wool Socks" })

      current_audit.record_tool_failure("check_structured_data", "HTTP 503")

      expect(current_audit.tool_failures).to eq("check_structured_data" => "HTTP 503")
      expect(current_audit.tool_results).to eq("get_product_data" => { title: "Cozy Wool Socks" })
    end
  end

  describe ".current" do
    it "returns whatever was assigned via .current=" do
      current_audit = build
      described_class.current = current_audit

      expect(described_class.current).to equal(current_audit)
    end

    it "fails loudly when nothing has been assigned, instead of silently returning nothing" do
      expect { described_class.current }.to raise_error(described_class::MissingError, /Auditor/)
    end
  end
end
