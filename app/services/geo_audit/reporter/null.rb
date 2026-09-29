module GeoAudit
  module Reporter
    # Does nothing. Used everywhere in specs so the suite stays quiet.
    class Null
      def event(name, **data)
      end
    end
  end
end
