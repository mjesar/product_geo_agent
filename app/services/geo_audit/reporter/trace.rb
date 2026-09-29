module GeoAudit
  module Reporter
    class Trace
      def initialize(path:, redactor: GeoAudit::Redactor.new, clock: -> { Time.now.utc })
        @path = path
        @redactor = redactor
        @clock = clock
      end

      def event(name, **data)
        redacted = @redactor.redact(plainify(data))
        append(JSON.generate(at: @clock.call.iso8601(3), event: name, data: redacted))
      end

      private

      # JSON can't encode a Data.define instance (Score::Result, Usage::Snapshot, ...)
      # directly, so anything hash/array-shaped recurses as-is, and anything else that
      # responds to to_h (every Data type here, plus DataMap, though DataMap is already
      # a Hash subclass so it's caught by the Hash branch first) gets flattened through
      # its own to_h before Redactor ever sees it.
      def plainify(value)
        case value
        when Hash
          value.to_h { |key, child| [ key.to_s, plainify(child) ] }
        when Array
          value.map { |item| plainify(item) }
        else
          value.respond_to?(:to_h) ? plainify(value.to_h) : value
        end
      end

      def append(line)
        FileUtils.mkdir_p(File.dirname(@path))
        File.open(@path, "a") { |file| file.puts(line) }
      end
    end
  end
end
