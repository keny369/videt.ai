# frozen_string_literal: true

module Platform
  # The ambient context a handler runs in: the injected clock and id generator
  # (so time and randomness are controllable in tests), the correlation id that
  # ties the command, result, audit and events together, and the acting service
  # identity. WF-001 grant issuance is always executed by the approved identity/
  # bootstrap service, so this context carries a service_identity_id.
  RequestContext = Data.define(:clock, :ids, :correlation_id, :service_identity_id) do
    def self.for_service(service_identity_id:, clock: Platform::Clock.system,
                         ids: Platform::Ids.system, correlation_id: nil)
      new(clock:, ids:, service_identity_id:, correlation_id: correlation_id || ids.generate)
    end

    # A Session-authenticated Organization actor (WF-013): the acting Account is
    # derived from the authenticated Session inside the handler, never carried here,
    # so this context bears no service identity.
    def self.for_actor(clock: Platform::Clock.system, ids: Platform::Ids.system, correlation_id: nil)
      new(clock:, ids:, service_identity_id: nil, correlation_id: correlation_id || ids.generate)
    end

    def now_utc = clock.now_utc
    def generate_id = ids.generate
  end
end
