require "rails_helper"

RSpec.describe GeoAudit::Eval::Comparator do
  let(:expectation) do
    GeoAudit::Eval::Expectations.new(
      "products" => {
        "cozy-wool-socks" => {
          "ratings" => {
            "description_quality" => { "accept" => [ "good" ], "expected" => "good" },
            "buyer_questions_answered" => { "accept" => [ "fair", "good" ], "expected" => "fair" },
            "specs_clarity" => { "accept" => [ "fair", "good" ] }
          },
          "facts" => {
            "alt_text" => { "with_alt" => 2, "of" => 3 },
            "faq_source" => "metafield",
            "structured_data" => false
          },
          "tools" => {
            "must_call" => [ "check_faq_page", "check_faq_metafield" ],
            "must_not_call" => [ "check_ai_citation" ]
          }
        }
      }
    ).fetch("cozy-wool-socks")
  end

  let(:ratings) do
    {
      "description_quality" => { "rating" => "good", "reason" => "Names material and fit." },
      "buyer_questions_answered" => { "rating" => "fair", "reason" => "Some questions covered." },
      "specs_clarity" => { "rating" => "good", "reason" => "Sizes are clear." }
    }
  end

  let(:tool_results) do
    {
      "get_product_data" => { images: [ "Wool sock", "Sock sole", nil ] },
      "check_faq_page" => { found: false },
      "check_faq_metafield" => { found: true },
      "check_structured_data" => { product_schema: true, product_schema_complete: false, faq_schema: false }
    }
  end

  def compare(ratings: self.ratings, tool_results: self.tool_results)
    described_class.new(expectation).call(ratings: ratings, tool_results: tool_results)
  end

  def compare_with(expectation, results)
    described_class.new(expectation).call(ratings: ratings, tool_results: results)
  end

  def check(result, kind, key)
    result.checks.find { |c| c.kind == kind && c.key == key }
  end

  it "passes every check when the run matches the expectations" do
    result = compare

    expect(result.handle).to eq("cozy-wool-socks")
    expect(result.checks.map(&:status).uniq).to eq([ :pass ])
    expect(result).not_to be_failed
    expect(result.off_expectation).to be_empty
  end

  describe "ratings" do
    it "fails a rating outside the accepted set" do
      result = compare(ratings: ratings.merge("description_quality" => { "rating" => "fair", "reason" => "x" }))

      expect(check(result, :rating, :description_quality)).to have_attributes(status: :fail, observed: "fair")
      expect(result).to be_failed
    end

    it "marks an accepted rating that is not the expected one as off-expectation, not a failure" do
      result = compare(ratings: ratings.merge("buyer_questions_answered" => { "rating" => "good", "reason" => "x" }))

      expect(check(result, :rating, :buyer_questions_answered).status).to eq(:off_expectation)
      expect(result.off_expectation.map(&:key)).to eq([ :buyer_questions_answered ])
      expect(result).not_to be_failed
    end

    it "treats any accepted rating as a pass when no single value was expected" do
      result = compare(ratings: ratings.merge("specs_clarity" => { "rating" => "fair", "reason" => "x" }))

      expect(check(result, :rating, :specs_clarity).status).to eq(:pass)
    end

    it "accepts ratings with symbol keys, the way the structured result may arrive" do
      result = compare(ratings: ratings.deep_symbolize_keys)

      expect(result).not_to be_failed
    end
  end

  describe "facts" do
    it "reads alt text as images with alt text out of all images" do
      expect(check(compare, :fact, :alt_text).observed).to eq(with_alt: 2, of: 3)
    end

    it "fails a fact that does not match" do
      result = compare(tool_results: tool_results.merge("get_product_data" => { images: [ "a", "b", "c" ] }))

      expect(check(result, :fact, :alt_text)).to have_attributes(status: :fail, observed: { with_alt: 3, of: 3 })
    end

    it "fails when the evidence was never produced, rather than guessing" do
      result = compare(tool_results: tool_results.except("get_product_data", "check_structured_data"))

      expect(check(result, :fact, :alt_text)).to have_attributes(status: :fail, observed: nil)
      expect(check(result, :fact, :structured_data)).to have_attributes(status: :fail, observed: nil)
    end

    it "tells a page FAQ from a metafield FAQ, and from none" do
      from_page = compare(tool_results: tool_results.merge("check_faq_page" => { found: true }))
      none = compare(tool_results: tool_results.merge("check_faq_metafield" => { found: false }))

      expect(check(from_page, :fact, :faq_source).observed).to eq("page")
      expect(check(none, :fact, :faq_source).observed).to eq("none")
    end

    it "counts structured data as found when the Product schema is complete or an FAQ schema exists" do
      complete = compare(tool_results: tool_results.merge("check_structured_data" => { product_schema_complete: true }))
      faq_only = compare(tool_results: tool_results.merge("check_structured_data" => { faq_schema: true }))

      expect(check(complete, :fact, :structured_data).observed).to be(true)
      expect(check(faq_only, :fact, :structured_data).observed).to be(true)
    end

    it "reads whether the AI mentioned the product" do
      expected_unmentioned = GeoAudit::Eval::Expectations.new(
        "products" => { "p" => { "ratings" => ratings.transform_values { |r| { "accept" => [ r["rating"] ] } },
                                 "facts" => { "ai_citation" => false } } }
      ).fetch("p")
      result = compare_with(expected_unmentioned, tool_results.merge("check_ai_citation" => { mentioned: true }))

      expect(check(result, :fact, :ai_citation)).to have_attributes(observed: true, status: :fail)
    end

    # The comparator re-reads tool results the way Score does. If Score's rule for
    # "found" ever changes and this does not follow, this is where it shows up.
    it "agrees with Score on whether each code-computed item was found" do
      cases = {
        faq_content: [ :faq_source, { "check_faq_page" => { found: true } }, { "check_faq_page" => { found: false } } ],
        structured_data: [ :structured_data, { "check_structured_data" => { product_schema_complete: true } },
                           { "check_structured_data" => { product_schema_complete: false } } ],
        ai_citation: [ :ai_citation, { "check_ai_citation" => { mentioned: true } },
                       { "check_ai_citation" => { mentioned: false } } ]
      }

      cases.each do |item, (fact, found, not_found)|
        { found => true, not_found => false }.each do |results, expected_found|
          scored = GeoAudit::Score.new(tool_results: results, ratings: ratings).call.items.find { |i| i.key == item }
          observed = check(compare_with(everything_expectation, results), :fact, fact).observed
          comparator_found = observed.present? && observed != "none"

          expect(scored.points.positive?).to eq(expected_found)
          expect(comparator_found).to eq(expected_found)
        end
      end
    end
  end

  describe "tool calls" do
    it "fails when a required tool was never called" do
      result = compare(tool_results: tool_results.except("check_faq_metafield"))

      expect(check(result, :tool, "check_faq_metafield")).to have_attributes(status: :fail, observed: "not called")
    end

    it "fails when a forbidden tool was called" do
      result = compare(tool_results: tool_results.merge("check_ai_citation" => { mentioned: false }))

      expect(check(result, :tool, "check_ai_citation")).to have_attributes(status: :fail, observed: "called")
    end
  end

  def everything_expectation
    GeoAudit::Eval::Expectations.new(
      "products" => {
        "p" => {
          "ratings" => ratings.transform_values { |r| { "accept" => [ r["rating"] ] } },
          "facts" => { "faq_source" => "page", "structured_data" => true, "ai_citation" => true }
        }
      }
    ).fetch("p")
  end
end
