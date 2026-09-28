module GeoAudit
  class ModelErrorRecovery
    # context.state is the only mutable, per-run bag little_ghost hands to hooks
    # (also where after_tool stashes tool results) — this key just keeps our own
    # bookkeeping out of the way of theirs.
    ATTEMPTS_KEY = :model_error_recovery_attempts

    def initialize(policy: RetryPolicy, sleeper: ->(seconds) { Kernel.sleep(seconds) })
      @policy = policy
      @sleeper = sleeper
    end

    def call(payload, context:)
      # context.state only stores JSON-shaped data (String/Symbol keys, no Ruby
      # default-hash tricks), so the turn number is stringified as the inner key,
      # keeping each turn's failures counted separately from every other turn's.
      #
      # Initializing and reading are kept as separate statements deliberately:
      # `context.state[K] ||= {}` evaluates to the plain `{}` literal, not the
      # DataMap that actually got stored, so mutating that expression's result
      # silently writes to an orphaned hash instead of the real state.
      context.state[ATTEMPTS_KEY] ||= {}
      attempts_by_turn = context.state[ATTEMPTS_KEY]
      turn_key = payload[:turn].to_s
      attempt = (attempts_by_turn[turn_key] || 0) + 1
      attempts_by_turn[turn_key] = attempt

      delay = @policy.delay_for(payload[:error], attempt:)
      return nil unless delay

      Usage.current_tracker&.record_retry!(:agent)
      @sleeper.call(delay)
      LittleGhost::Support::Callbacks.replace({ request: payload[:request] })
    end
  end
end
