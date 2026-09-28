module GeoAudit
  class ModelCallCounter
    def call(_payload, context:)
      Usage.current_tracker&.record_call!(:agent)
      nil
    end
  end
end
