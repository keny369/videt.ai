# frozen_string_literal: true

require "digest"
require "json"

module Workflows
  module Wf004
    module Handlers
      # WF-004 RegisterSource (WORKFLOW_SPECIFICATIONS.md :398-408, :704; CAP-004
      # MTX-004; contracts/S-04.json). One proposed Source is registered against a
      # Project from one absolute HTTPS root URI, idempotently, with exactly one
      # SourceRegistered event and immutable provenance.
      #
      # The first-match order (contracts/S-04.json error_contract) is honoured as:
      # the ten schema/URI/host reasons (decided from input alone, before any tenant
      # read), then the authentication reasons, then `project_not_registerable`,
      # `tenant_mismatch`, `source_register_unauthorized`, `stale_state_version`,
      # and finally the uniqueness/replay outcomes. A not-found Project — another
      # Organization's or nonexistent — is invisible under RLS and is refused as
      # `tenant_mismatch` without disclosing which.
      #
      # This is registration only. It creates one Source in `proposed` and never
      # verifies, activates, crawls or creates Evidence; those are S-05/S-06.
      class RegisterSource
        include SourceLedger

        SUPPORTED_SCHEMA_MAJOR = "1"
        TARGET_TYPE = "source"
        ACTION = "source.register"
        CAPABILITY = "source.register"
        REGISTERABLE_PROJECT_STATES = %w[draft active paused].freeze

        def call(command:, request_context:)
          ctx = request_context
          return schema_failure(command, ctx) unless schema_supported?(command)

          uri = SourceRegistration.validate(command.submitted_root_uri)
          return in_memory_failure(command, ctx, uri.reason) unless uri.ok?

          Platform::UnitOfWork.run do |conn|
            pg = conn.raw_connection
            now = ctx.now_utc.floor(6)
            auth_store = IdentityAccess::Infrastructure::AuthorizationStore.new(pg)
            auth = IdentityAccess::Authorization::CommandAuthorizer.new(auth_store)
            store = IdentityAccess::Infrastructure::SourceStore.new(pg)

            actor = auth.authenticate(session_id: command.session_id, now:, correlation_id: ctx.correlation_id)
            return in_memory_failure(command, ctx, actor.to_s) if actor.is_a?(Symbol)

            request_sha256 = request_hash(command, uri.canonical_host, actor)
            d = { command:, ctx:, store:, auth_store:, actor:, org: actor.organization_id, now:, request_sha256: }
            process(d, auth, uri)
          end
        end

        private

        # The command's envelope major and its declared registration schema must
        # both be the source-registration-v1 contract; either being unsupported is
        # `source_request_schema_unsupported`.
        def schema_supported?(command)
          SourceRegistration.supported_schema?(command.schema_version) &&
            command.registration_schema_version == SourceRegistration::REGISTRATION_SCHEMA_VERSION
        end

        def process(d, auth, uri)
          command = d[:command]
          store = d[:store]
          actor = d[:actor]
          now = d[:now]

          project = store.project(command.project_id)
          # Not found in the actor's proved context: another Organization's or
          # nonexistent, refused without disclosure.
          return denied(d, "tenant_mismatch") if project.nil? || project["organization_id"] != actor.organization_id
          unless REGISTERABLE_PROJECT_STATES.include?(project["state"])
            return denied(d, "project_not_registerable")
          end
          return denied(d, "tenant_mismatch") unless command.organization_id == actor.organization_id

          decision = auth.authorize(actor:, capability: CAPABILITY, now:)
          d = d.merge(decision:)
          unless decision.allowed?
            outward = decision.reason == "missing_authority" ? "source_register_unauthorized" : decision.reason
            return deny(**denial_args(d), resource_id: command.project_id, outward:, internal: outward)
          end

          unless project["state_version"].to_i == command.expected_state_version
            return denied(d, "stale_state_version")
          end

          store.lock_source_host(command.project_id, uri.canonical_host)

          key_digest = Digest::SHA256.digest(command.idempotency_key)
          existing = store.find_idempotency(org: d[:org], command_type: command.command_type,
                                            target_type: TARGET_TYPE, target_id: command.project_id, key_digest:)
          return replay(store, command, existing) if existing && existing["request_hex"] == hex(d[:request_sha256])
          if store.host_registered?(d[:org], command.project_id, uri.canonical_host)
            return denied(d, "source_host_already_registered")
          end
          return denied(d, "idempotency_conflict") if existing

          commit(d, uri, key_digest)
        end

        def commit(d, uri, key_digest)
          command = d[:command]
          ctx = d[:ctx]
          store = d[:store]
          org = d[:org]
          now = d[:now]
          actor = d[:actor]
          request_sha256 = d[:request_sha256]

          ids = %i[source execution audit event result decision idem].to_h { |k| [k, ctx.generate_id] }
          write_execution(store, command, ctx, org, ids[:execution], ids[:source], actor, request_sha256,
                          key_digest, now, ACTION)
          write_authorization_decision(d[:auth_store], ids[:decision], ctx, command, actor, d[:decision], now,
                                       ids[:source], ACTION)
          store.insert_source(
            id: ids[:source], now:, correlation_id: ctx.correlation_id, organization_id: org,
            project_id: command.project_id, submitted_root_uri: command.submitted_root_uri,
            canonical_root_uri: uri.canonical_root_uri, canonical_host: uri.canonical_host,
            registration_schema_version: SourceRegistration::REGISTRATION_SCHEMA_VERSION,
            host_normalization_version: SourceRegistration::HOST_NORMALIZATION_VERSION,
            registering_account_id: actor.account_id, registration_command_id: command.command_id,
            registration_idempotency_key_digest: key_digest,
            registration_authorization_decision_id: ids[:decision]
          )

          payload = { "source_id" => ids[:source], "project_id" => command.project_id, "organization_id" => org,
                      "canonical_host" => uri.canonical_host, "canonical_root_uri" => uri.canonical_root_uri,
                      "registration_schema_version" => SourceRegistration::REGISTRATION_SCHEMA_VERSION,
                      "host_normalization_version" => SourceRegistration::HOST_NORMALIZATION_VERSION,
                      "state" => "proposed", "state_version" => 0 }
          write_audit(store, ids[:audit], org, ctx, command, ids[:source], actor,
                      to_state: "proposed", outcome: "success", reason_code: nil, payload:, now:)
          write_event(store, ids, org, ctx, command, actor, now, 0, ids[:source], request_sha256, key_digest,
                      "SourceRegistered", "created",
                      { "canonical_host" => uri.canonical_host, "canonical_root_uri" => uri.canonical_root_uri,
                        "registration_schema_version" => SourceRegistration::REGISTRATION_SCHEMA_VERSION,
                        "host_normalization_version" => SourceRegistration::HOST_NORMALIZATION_VERSION,
                        "to_state" => "proposed" })
          write_result_success(store, ids, command, ctx, org, actor, now, payload, ids[:source])
          write_idempotency(store, ids[:idem], org, command, command.project_id, key_digest, request_sha256,
                            ids[:execution], ids[:result], now)

          Platform::CommandResult.success(result_id: ids[:result], command_type: command.command_type,
                                          audit_record_id: ids[:audit], correlation_id: ctx.correlation_id,
                                          payload: payload.transform_keys(&:to_sym))
        end

        # A denial whose authorization decision is an allow (a tenant/state/duplicate
        # refusal of an authorized actor) or precedes the capability evaluation.
        # Both are recorded with the real decision, defaulting to a synthesized
        # not-yet-evaluated decision when the refusal is before authorize.
        def denied(d, reason)
          decision = d[:decision] || pre_authorization_decision(d[:actor])
          deny(**denial_args(d.merge(decision:)), resource_id: d[:command].project_id, outward: reason, internal: reason)
        end

        def denial_args(d)
          { command: d[:command], ctx: d[:ctx], store: d[:store], auth_store: d[:auth_store], actor: d[:actor],
            decision: d[:decision], org: d[:org], now: d[:now], request_sha256: d[:request_sha256] }
        end

        # For refusals reached before the capability is evaluated (tenant/state),
        # the durable authorization decision records that no capability check was
        # performed yet, keeping the audit trail honest.
        def pre_authorization_decision(actor)
          IdentityAccess::Authorization::Decision.new(
            allowed: false, reason: "not_evaluated", organization_epoch: actor.authorization_epoch,
            policy_snapshot_id: nil, role_assignment_versions: [], granting_assignments: []
          )
        end

        def replay(store, command, existing)
          stored = store.load_command_result(existing["command_result_id"])
          payload = JSON.parse(stored["authorized_payload"]).transform_keys(&:to_sym)
          Platform::CommandResult.success(result_id: stored["id"], command_type: command.command_type,
                                          payload:, audit_record_id: stored["audit_record_id"],
                                          correlation_id: stored["correlation_id"], replayed: true)
        end

        # The canonical request hash: the shared envelope plus the canonical host
        # and the registration schema as `command_payload`, and the Project's
        # expected state version in the envelope's expected-version slot. Generated
        # identifiers, the idempotency key, the requested time and transport
        # metadata are excluded, so a replay under a new command_id is still a
        # replay and a different host under the same key is a conflict.
        def request_hash(command, canonical_host, actor)
          Platform::CanonicalJson.digest({
            "action" => ACTION, "command_type" => command.command_type,
            "command_schema_version" => command.schema_version, "actor_id" => actor.account_id,
            "organization_id" => actor.organization_id, "target_type" => TARGET_TYPE,
            "target_id" => nil, "project_id" => command.project_id,
            "expected_version" => command.expected_state_version,
            "policy_versions" => [Platform::PermissionBaseline::VERSION],
            "command_payload" => {
              "registration_schema_version" => command.registration_schema_version,
              "canonical_host" => canonical_host
            }
          })
        end
      end
    end
  end
end
