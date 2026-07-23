# frozen_string_literal: true

require "digest"
require "json"

module Workflows
  module Wf002
    module Handlers
      # WF-002 CreateProject (WORKFLOW_SPECIFICATIONS.md :648-659; CAP-003 MTX-003;
      # PRULE-003 MTX-054). One draft Project is created in the caller's active
      # Organization from a complete `project-profile-v1` body, idempotently, with
      # exactly one ProjectCreated event.
      #
      # The creation first-match order (contracts/S-03.json MTX-027 error_contract)
      # is honoured as: the eight profile/shape reasons (decided from input alone,
      # before any tenant read), then the authentication reasons, then
      # `project_create_unauthorized`, `tenant_mismatch`, `idempotency_conflict`.
      # The one reason that cannot be decided from input alone —
      # `project_local_profile_invalid` for a business name that differs from the
      # Organization display name — is applied after authentication, because
      # resolving the Organization display name requires the proved context; it can
      # never be evaluated for an unauthenticated caller without leaking tenant
      # state, so it deterministically follows authentication rather than preceding
      # it. `stale_state_version` is listed by the shared order but is unreachable
      # in creation, which takes no expected version.
      #
      # This is CreateProject only. Activation (draft->active) is a distinct, later
      # command whose prerequisite is an active same-Project Source (CAP-003),
      # owned by S-04/S-05/S-06 and not built; the projects lifecycle guard refuses
      # every state change until that slice lands.
      class CreateProject
        include ProjectLedger

        SUPPORTED_SCHEMA_MAJOR = "1"
        TARGET_TYPE = "project"
        ACTION = "project.create"
        CAPABILITY = "project.create"

        def call(command:, request_context:)
          ctx = request_context
          return schema_failure(command, ctx) unless ProjectCreation.supported_schema?(command.schema_version)

          outcome = ProjectCreation.validate(command.profile)
          return in_memory_failure(command, ctx, outcome.reason) unless outcome.ok?

          normalized = outcome.profile
          Platform::UnitOfWork.run do |conn|
            pg = conn.raw_connection
            now = ctx.now_utc.floor(6)
            auth_store = IdentityAccess::Infrastructure::AuthorizationStore.new(pg)
            auth = IdentityAccess::Authorization::CommandAuthorizer.new(auth_store)
            store = IdentityAccess::Infrastructure::ProjectStore.new(pg)

            actor = auth.authenticate(session_id: command.session_id, now:, correlation_id: ctx.correlation_id)
            return in_memory_failure(command, ctx, actor.to_s) if actor.is_a?(Symbol)

            decision = auth.authorize(actor:, capability: CAPABILITY, now:)
            request_sha256 = request_hash(command, normalized, actor)
            d = { command:, ctx:, store:, auth_store:, actor:, decision:, org: actor.organization_id,
                  now:, request_sha256: }
            unless decision.allowed?
              outward = decision.reason == "missing_authority" ? "project_create_unauthorized" : decision.reason
              return deny(**d, outward:, internal: outward)
            end

            process(d, normalized)
          end
        end

        private

        def process(d, normalized)
          command = d[:command]
          store = d[:store]
          org = d[:org]

          unless command.organization_id == org
            return deny(**d, outward: "tenant_mismatch", internal: "tenant_mismatch")
          end

          unless ProjectCreation.business_name_matches?(normalized, store.organization_display_name(org))
            return deny(**d, outward: "project_local_profile_invalid", internal: "project_local_profile_invalid")
          end

          store.lock_organization(org)

          key_digest = Digest::SHA256.digest(command.idempotency_key)
          existing = store.find_idempotency(org:, command_type: command.command_type, target_type: TARGET_TYPE,
                                            target_id: org, key_digest:)
          if existing
            return replay(store, command, existing) if existing["request_hex"] == hex(d[:request_sha256])

            return deny(**d, outward: "idempotency_conflict", internal: "idempotency_conflict")
          end

          commit(d, normalized, key_digest)
        end

        def commit(d, normalized, key_digest)
          command = d[:command]
          ctx = d[:ctx]
          store = d[:store]
          org = d[:org]
          now = d[:now]
          actor = d[:actor]
          request_sha256 = d[:request_sha256]

          ids = %i[project execution audit event result decision idem].to_h { |k| [k, ctx.generate_id] }
          content_sha = ProjectCreation.content_sha256(normalized)

          write_execution(store, command, ctx, org, ids[:execution], ids[:project], actor, request_sha256,
                          key_digest, now, ACTION)
          write_authorization_decision(d[:auth_store], ids[:decision], ctx, command, actor, d[:decision], now,
                                       ids[:project], ACTION)
          store.insert_project(
            id: ids[:project], now:, correlation_id: ctx.correlation_id, organization_id: org,
            display_name: normalized["display_name"], locale: normalized["default_locale"],
            time_zone: normalized["reporting_time_zone"], objective: normalized["objective"],
            project_profile_schema_version: normalized["project_profile_schema_version"],
            local_presence_applicable: normalized["local_presence_applicable"],
            local_presence_reason: normalized["local_presence_reason"],
            local_business_profile: normalized["local_business_profile"],
            local_business_profile_content_sha256: content_sha,
            profile_attesting_account_id: actor.account_id
          )

          payload = { "project_id" => ids[:project], "organization_id" => org, "state" => "draft",
                      "state_version" => 0, "display_name" => normalized["display_name"],
                      "local_presence_applicable" => normalized["local_presence_applicable"] }
          write_audit(store, ids[:audit], org, ctx, command, ids[:project], actor,
                      to_state: "draft", outcome: "success", reason_code: nil, payload:, now:)
          write_event(store, ids, org, ctx, command, actor, now, 0, ids[:project], request_sha256, key_digest,
                      "ProjectCreated", "created", { "to_state" => "draft" })
          write_result_success(store, ids, command, ctx, org, actor, now, payload, ids[:project])
          write_idempotency(store, ids[:idem], org, command, org, key_digest, request_sha256, ids[:execution],
                            ids[:result], now)

          Platform::CommandResult.success(result_id: ids[:result], command_type: command.command_type,
                                          audit_record_id: ids[:audit], correlation_id: ctx.correlation_id,
                                          payload: payload.transform_keys(&:to_sym))
        end

        def replay(store, command, existing)
          stored = store.load_command_result(existing["command_result_id"])
          payload = JSON.parse(stored["authorized_payload"]).transform_keys(&:to_sym)
          Platform::CommandResult.success(result_id: stored["id"], command_type: command.command_type,
                                          payload:, audit_record_id: stored["audit_record_id"],
                                          correlation_id: stored["correlation_id"], replayed: true)
        end

        # The canonical request hash: the shared envelope plus the normalized
        # profile as `command_payload`. Generated identifiers, the idempotency key,
        # the requested time and transport metadata are excluded, so a replay under
        # a new command_id is still a replay and an altered profile under the same
        # key is a conflict. Creation carries no expected version, so the envelope's
        # expected-version slot is null.
        def request_hash(command, normalized, actor)
          Platform::CanonicalJson.digest({
            "action" => ACTION, "command_type" => command.command_type,
            "command_schema_version" => command.schema_version, "actor_id" => actor.account_id,
            "organization_id" => actor.organization_id, "target_type" => TARGET_TYPE,
            "target_id" => nil, "project_id" => nil, "expected_authorization_epoch" => nil,
            "policy_versions" => [Platform::PermissionBaseline::VERSION],
            "command_payload" => normalized
          })
        end
      end
    end
  end
end
