module GeoAudit
  module Reporter
    class Multi
      def initialize(*reporters)
        @reporters = reporters
      end

      def event(name, **data)
        @reporters.each { |reporter| reporter.event(name, **data) }
        nil
      end
    end
  end
end
