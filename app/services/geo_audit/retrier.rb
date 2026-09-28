module GeoAudit
  class Retrier
    # sleeper is injectable so specs never actually wait out a real backoff delay.
    # tracker/part are optional: nil by default so existing callers are unaffected,
    # and are the only place a bare LittleGhost.generate call's usage is visible
    # before CitationCheck/GapsExplanation reduce the response down to text.
    def initialize(policy: RetryPolicy, sleeper: ->(seconds) { Kernel.sleep(seconds) }, tracker: nil, part: nil)
      @policy = policy
      @sleeper = sleeper
      @tracker = tracker
      @part = part
    end

    def call(attempt: 1, &block)
      @tracker&.record_call!(@part)
      result = block.call
      @tracker&.record_tokens(@part, result.usage) if result.respond_to?(:usage)
      result
    rescue => error
      delay = @policy.delay_for(error, attempt:)
      raise unless delay

      @tracker&.record_retry!(@part)
      @sleeper.call(delay)
      call(attempt: attempt + 1, &block)
    end
  end
end
