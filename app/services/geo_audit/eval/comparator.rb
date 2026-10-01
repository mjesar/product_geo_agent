module GeoAudit
  module Eval
    # Compares ONE real audit run against one product's hand-written expectations.
    # No model, no network: it only reads the run's ratings and tool results, so it
    # can be tested without spending any quota. Turning several runs into a spread
    # (stable, flaky, failing) is the report's job, not this class's.
    class Comparator
      # status is :pass, :off_expectation (inside the accepted set but not the single
      # value that was predicted, ratings only) or :fail. observed is nil when the run
      # never produced the evidence, which counts as a fail, not a pass.
      Check = Data.define(:kind, :key, :expected, :observed, :status)

      Result = Data.define(:handle, :checks) do
        def failed?
          checks.any? { |check| check.status == :fail }
        end

        def off_expectation
          checks.select { |check| check.status == :off_expectation }
        end
      end

      def initialize(expectation)
        @expectation = expectation
      end

      def call(ratings:, tool_results:)
        ratings = ratings.deep_symbolize_keys
        tool_results = tool_results.deep_symbolize_keys
        checks = rating_checks(ratings) + fact_checks(tool_results) + tool_checks(tool_results)

        Result.new(handle: @expectation.handle, checks: checks)
      end

      private

      def rating_checks(ratings)
        @expectation.ratings.map do |item, rating|
          observed = ratings.dig(item, :rating)
          status =
            if !rating.accept.include?(observed) then :fail
            elsif rating.expected && observed != rating.expected then :off_expectation
            else :pass
            end

          Check.new(kind: :rating, key: item, expected: rating, observed: observed, status: status)
        end
      end

      def fact_checks(tool_results)
        @expectation.facts.map do |key, expected|
          observed = observed_fact(key, tool_results)

          Check.new(kind: :fact, key: key, expected: expected, observed: observed,
                    status: (observed == expected) ? :pass : :fail)
        end
      end

      # Mirrors how Score reads the same tool results, so a fact here means the same
      # thing as the rubric item it feeds. A tool that never ran gives nil.
      def observed_fact(key, tool_results)
        case key
        when :alt_text then observed_alt_text(tool_results)
        when :faq_source then observed_faq_source(tool_results)
        when :structured_data
          result = tool_results[:check_structured_data]
          result && !!(result[:product_schema_complete] || result[:faq_schema])
        when :ai_citation
          tool_results.dig(:check_ai_citation, :mentioned)
        end
      end

      def observed_alt_text(tool_results)
        images = tool_results.dig(:get_product_data, :images)
        images && { with_alt: images.count(&:present?), of: images.size }
      end

      def observed_faq_source(tool_results)
        if tool_results.dig(:check_faq_page, :found) then "page"
        elsif tool_results.dig(:check_faq_metafield, :found) then "metafield"
        elsif tool_results.key?(:check_faq_page) then "none"
        end
      end

      def tool_checks(tool_results)
        called = ->(name) { tool_results.key?(name.to_sym) }

        @expectation.must_call.map do |name|
          Check.new(kind: :tool, key: name, expected: "called", observed: called.(name) ? "called" : "not called",
                    status: called.(name) ? :pass : :fail)
        end + @expectation.must_not_call.map do |name|
          Check.new(kind: :tool, key: name, expected: "not called", observed: called.(name) ? "called" : "not called",
                    status: called.(name) ? :fail : :pass)
        end
      end
    end
  end
end
