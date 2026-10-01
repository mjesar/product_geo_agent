module GeoAudit
  module Eval
    # Reads the hand-written ground truth the eval harness compares real audit runs
    # against (spec/evals/expectations.yml). It only loads and validates: a typo in a
    # hand-written file should fail loudly here, not silently weaken an eval by
    # leaving an expectation unchecked.
    class Expectations
      class Invalid < StandardError; end

      ProductExpectation = Data.define(:handle, :fingerprint, :ratings, :facts, :must_call, :must_not_call)

      # The three items the model judges. The rest of the rubric is computed in code
      # from tool results, so those are recorded as facts, not allowed-rating sets.
      RATED_ITEMS = %w[description_quality buyer_questions_answered specs_clarity].freeze
      FACT_KEYS = %w[alt_text faq_source structured_data ai_citation].freeze
      FAQ_SOURCES = %w[page metafield none].freeze
      PRODUCT_KEYS = %w[fingerprint ratings facts tools].freeze
      TOOL_KEYS = %w[must_call must_not_call].freeze

      attr_reader :products

      def self.load(path)
        new(YAML.safe_load_file(path) || {})
      end

      def initialize(data)
        require_hash!(data, "top level")
        reject_unknown_keys!(data, %w[products], "top level")
        products = data["products"] || {}
        require_hash!(products, "products")

        @products = products.to_h { |handle, spec| [ handle, build(handle, spec) ] }.freeze
      end

      def fetch(handle)
        @products.fetch(handle) { raise Invalid, "no expectations for handle #{handle.inspect}" }
      end

      private

      def build(handle, spec)
        where = "products.#{handle}"
        require_hash!(spec, where)
        reject_unknown_keys!(spec, PRODUCT_KEYS, where)
        tools = spec["tools"] || {}
        require_hash!(tools, "#{where}.tools")
        reject_unknown_keys!(tools, TOOL_KEYS, "#{where}.tools")

        must_call = tool_list(tools["must_call"], "#{where}.tools.must_call")
        must_not_call = tool_list(tools["must_not_call"], "#{where}.tools.must_not_call")
        overlap = must_call & must_not_call
        raise Invalid, "#{where}.tools: #{overlap.join(', ')} is in both must_call and must_not_call" if overlap.any?

        ProductExpectation.new(
          handle: handle,
          fingerprint: fingerprint(spec["fingerprint"], where),
          ratings: ratings(spec["ratings"], where),
          facts: facts(spec["facts"] || {}, where),
          must_call: must_call,
          must_not_call: must_not_call
        )
      end

      # Optional until the harness can compute it: a hash of the product's content, so
      # a later edit in the store reads as "product changed", not a failing agent.
      def fingerprint(value, where)
        return nil if value.nil?
        raise Invalid, "#{where}.fingerprint must be a string" unless value.is_a?(String)

        value
      end

      # Required, all three: a missing item would quietly go unchecked, and deciding
      # what you expect for each judged item before the first run is the point.
      def ratings(value, where)
        require_hash!(value, "#{where}.ratings")
        reject_unknown_keys!(value, RATED_ITEMS, "#{where}.ratings")
        missing = RATED_ITEMS - value.keys
        raise Invalid, "#{where}.ratings is missing #{missing.join(', ')}" if missing.any?

        value.to_h { |item, allowed| [ item.to_sym, allowed_ratings(allowed, "#{where}.ratings.#{item}") ] }
      end

      def allowed_ratings(value, where)
        valid = Score::RATING_POINTS.keys
        unless value.is_a?(Array) && value.any? && (value - valid).empty?
          raise Invalid, "#{where} must be a non-empty list drawn from #{valid.join(', ')}"
        end

        value.uniq
      end

      # Optional per key: a fact left out is simply not checked.
      def facts(value, where)
        require_hash!(value, "#{where}.facts")
        reject_unknown_keys!(value, FACT_KEYS, "#{where}.facts")

        value.to_h { |key, expected| [ key.to_sym, fact(key, expected, "#{where}.facts.#{key}") ] }
      end

      def fact(key, expected, where)
        case key
        when "alt_text" then alt_text_fact(expected, where)
        when "faq_source"
          raise Invalid, "#{where} must be one of #{FAQ_SOURCES.join(', ')}" unless FAQ_SOURCES.include?(expected)

          expected
        else
          raise Invalid, "#{where} must be true or false" unless [ true, false ].include?(expected)

          expected
        end
      end

      def alt_text_fact(expected, where)
        require_hash!(expected, where)
        reject_unknown_keys!(expected, %w[with_alt of], where)
        with_alt, total = expected.values_at("with_alt", "of")
        unless with_alt.is_a?(Integer) && total.is_a?(Integer) && with_alt.between?(0, total)
          raise Invalid, "#{where} needs integers with_alt and of, with 0 <= with_alt <= of"
        end

        { with_alt: with_alt, of: total }
      end

      def tool_list(value, where)
        return [] if value.nil?

        known = GeoAuditAgent.tools.map(&:tool_name)
        unless value.is_a?(Array) && (value - known).empty?
          raise Invalid, "#{where} must be a list of tool names from #{known.join(', ')}"
        end

        value.uniq
      end

      def require_hash!(value, where)
        raise Invalid, "#{where} must be a mapping" unless value.is_a?(Hash)
      end

      def reject_unknown_keys!(hash, allowed, where)
        unknown = hash.keys - allowed
        raise Invalid, "#{where} has unknown key(s) #{unknown.join(', ')} (allowed: #{allowed.join(', ')})" if unknown.any?
      end
    end
  end
end
