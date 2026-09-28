module GeoAudit
  class RetryPolicy
    DELAYS = {
      503 => [5, 15, 30].freeze,
      429 => [15, 30, 60].freeze
    }.freeze

    def self.delay_for(error, attempt:)
      return nil unless error.is_a?(LittleGhost::Providers::HTTPError)

      # Array#at returns nil past the last delay, which is also our "stop retrying" signal.
      DELAYS.fetch(error.status, []).at(attempt - 1)
    end
  end
end
