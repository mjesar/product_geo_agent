require "rails_helper"

RSpec.describe GeoAudit::Eval::Expectations do
  let(:valid_product) do
    {
      "fingerprint" => "abc123",
      "ratings" => {
        "description_quality" => [ "good" ],
        "buyer_questions_answered" => [ "fair", "good" ],
        "specs_clarity" => [ "fair", "good" ]
      },
      "facts" => {
        "alt_text" => { "with_alt" => 2, "of" => 3 },
        "faq_source" => "metafield",
        "structured_data" => false,
        "ai_citation" => false
      },
      "tools" => {
        "must_call" => [ "check_faq_page", "check_faq_metafield" ],
        "must_not_call" => [ "check_ai_citation" ]
      }
    }
  end

  def build(product)
    described_class.new({ "products" => { "cozy-wool-socks" => product } })
  end

  describe "a valid product" do
    subject(:product) { build(valid_product).fetch("cozy-wool-socks") }

    it "keeps the handle and fingerprint" do
      expect(product.handle).to eq("cozy-wool-socks")
      expect(product.fingerprint).to eq("abc123")
    end

    it "keys the allowed ratings by item, as symbols" do
      expect(product.ratings).to eq(
        description_quality: [ "good" ],
        buyer_questions_answered: [ "fair", "good" ],
        specs_clarity: [ "fair", "good" ]
      )
    end

    it "keeps the expected facts" do
      expect(product.facts).to eq(
        alt_text: { with_alt: 2, of: 3 }, faq_source: "metafield", structured_data: false, ai_citation: false
      )
    end

    it "keeps the expected tool calls" do
      expect(product.must_call).to eq([ "check_faq_page", "check_faq_metafield" ])
      expect(product.must_not_call).to eq([ "check_ai_citation" ])
    end
  end

  describe "optional parts" do
    it "defaults facts, tools and fingerprint when they are left out" do
      product = build(valid_product.slice("ratings")).fetch("cozy-wool-socks")

      expect(product.fingerprint).to be_nil
      expect(product.facts).to eq({})
      expect(product.must_call).to eq([])
      expect(product.must_not_call).to eq([])
    end

    it "loads an empty file, or one with no products" do
      expect(described_class.new({}).products).to eq({})
      expect(described_class.new({ "products" => nil }).products).to eq({})
    end
  end

  describe "rejecting a bad file" do
    it "rejects a missing rated item" do
      product = valid_product.deep_dup
      product["ratings"].delete("specs_clarity")

      expect { build(product) }.to raise_error(described_class::Invalid, /ratings is missing specs_clarity/)
    end

    it "rejects a rating that is not poor, fair or good" do
      product = valid_product.deep_dup
      product["ratings"]["specs_clarity"] = [ "great" ]

      expect { build(product) }.to raise_error(described_class::Invalid, /specs_clarity must be a non-empty list/)
    end

    it "rejects an empty allowed list" do
      product = valid_product.deep_dup
      product["ratings"]["specs_clarity"] = []

      expect { build(product) }.to raise_error(described_class::Invalid, /specs_clarity must be a non-empty list/)
    end

    it "rejects an unknown key, so a typo cannot silently skip a check" do
      product = valid_product.deep_dup
      product["rating"] = product.delete("ratings")

      expect { build(product) }.to raise_error(described_class::Invalid, /unknown key\(s\) rating/)
    end

    it "rejects an unknown fact" do
      product = valid_product.deep_dup
      product["facts"]["shipping"] = true

      expect { build(product) }.to raise_error(described_class::Invalid, /facts has unknown key\(s\) shipping/)
    end

    it "rejects a faq_source that is not page, metafield or none" do
      product = valid_product.deep_dup
      product["facts"]["faq_source"] = "sidebar"

      expect { build(product) }.to raise_error(described_class::Invalid, /faq_source must be one of/)
    end

    it "rejects a yes/no fact that is not a boolean" do
      product = valid_product.deep_dup
      product["facts"]["ai_citation"] = "no"

      expect { build(product) }.to raise_error(described_class::Invalid, /ai_citation must be true or false/)
    end

    it "rejects alt text counts that cannot be true" do
      product = valid_product.deep_dup
      product["facts"]["alt_text"] = { "with_alt" => 4, "of" => 3 }

      expect { build(product) }.to raise_error(described_class::Invalid, /with_alt <= of/)
    end

    it "rejects a tool the agent does not have" do
      product = valid_product.deep_dup
      product["tools"]["must_call"] = [ "check_shipping" ]

      expect { build(product) }.to raise_error(described_class::Invalid, /must be a list of tool names/)
    end

    it "rejects a tool listed as both required and forbidden" do
      product = valid_product.deep_dup
      product["tools"]["must_not_call"] = [ "check_faq_page" ]

      expect { build(product) }.to raise_error(described_class::Invalid, /check_faq_page is in both/)
    end

    it "names the product in the error so a hand-written file is easy to fix" do
      expect { build(valid_product.except("ratings")) }.to raise_error(described_class::Invalid, /products\.cozy-wool-socks\.ratings/)
    end
  end

  describe "#fetch" do
    it "raises for a handle with no expectations" do
      expect { build(valid_product).fetch("no-such-socks") }.to raise_error(described_class::Invalid, /no-such-socks/)
    end
  end

  describe ".load" do
    it "reads and validates a YAML file" do
      path = Rails.root.join("tmp", "expectations_spec.yml")
      File.write(path, { "products" => { "cozy-wool-socks" => valid_product } }.to_yaml)

      expect(described_class.load(path).fetch("cozy-wool-socks").handle).to eq("cozy-wool-socks")
    ensure
      FileUtils.rm_f(path)
    end

    it "accepts the real expectations file, so a typo there fails the suite" do
      expect { described_class.load(Rails.root.join("spec", "evals", "expectations.yml")) }.not_to raise_error
    end
  end
end
