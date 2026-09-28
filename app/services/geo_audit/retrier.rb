module GeoAudit
  class Retrier
    # sleeper is injectable so specs never actually wait out a real backoff delay.
    def initialize(policy: RetryPolicy, sleeper: ->(seconds) { Kernel.sleep(seconds) })
      @policy = policy
      @sleeper = sleeper
    end

    def call(attempt: 1, &block)
      block.call
    rescue => error
      delay = @policy.delay_for(error, attempt:)
      raise unless delay

      @sleeper.call(delay)
      call(attempt: attempt + 1, &block)
    end
  end
end
