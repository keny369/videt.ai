# frozen_string_literal: true

require "digest"
require "json"
require "time"

module Workflows
  module Wf001
    module Handlers
      # WF-001 self-service BootstrapOrganization (WORKFLOW_SPECIFICATIONS.md :238,
      # :627-641; CAP-002 / PRULE-002). The whole tenant genesis in one atomic
      # commit, under a valid Bootstrap Grant, service-attributed to the approved
      # bootstrap service, with no billing-provider call.
      #
      # The ordering inside the commit is normative (:628): Organization pending,
      # Account pending, BillingEntity pending, the null-expiry first
      # OrganizationAdmin Assignment, active access-policy-v1, active
      # entitlement-interim-v1 plus its BillingEntity-linked Plan Assignment, and
      # the draft Project; then activate BillingEntity, activate Account and
      # Organization, consume the grant and receipt nonce, and create the Session.
      # The thirteen events are emitted in their fixed order (:641).
      #
      # Every genesis row and every event either all commit or none do: a failure
      # at any point rolls the transaction back and exposes no tenant record.
      class BootstrapOrganization
        SUPPORTED_SCHEMA_MAJOR = "1"
        POLICY_VERSION = "onboarding-interim-v1"
        SERVICE = Platform::ServiceIdentity::IDENTITY_SERVICE
        ACTION = "organization.bootstrap"
        RECEIPT_PURPOSE = "self_service_bootstrap"
        APPROVED_ISSUERS = ["https://id.example/oidc"].freeze
        ORG_SCOPE = Digest::SHA256.digest("scope:organization")

        def call(command:, request_context:)
          ctx = request_context
          return schema_failure(command, ctx) unless supported_schema?(command.schema_version)

          reason = validate_inputs(command)
          return in_memory_failure(command, ctx, reason) if reason

          Platform::UnitOfWork.run do |conn|
            store = IdentityAccess::Infrastructure::OrganizationGenesisStore.new(conn.raw_connection)
            organization_id = ctx.generate_id
            receipt = store.enter_self_service_context(receipt_digest: command.receipt_digest,
                                                       organization_id:, correlation_id: ctx.correlation_id)
            return in_memory_failure(command, ctx, "identity_receipt_invalid") if receipt.nil?

            bootstrap(command:, ctx:, store:, organization_id:, receipt:)
          end
        end

        private

        # ---- input validation (before any context) ------------------------------

        def validate_inputs(command)
          return "organization_profile_invalid" unless valid_display_name?(command.organization_display_name)
          return "project_body_invalid" unless valid_display_name?(command.project_display_name)
          return "access_policy_hash_mismatch" unless command.access_policy_content_sha256 == Platform::BaselineContent.access_policy_sha256
          return "entitlement_policy_hash_mismatch" unless command.entitlement_policy_content_sha256 == Platform::BaselineContent.entitlement_policy_sha256
          return "plan_hash_mismatch" unless command.plan_content_sha256 == Platform::BaselineContent.plan_sha256

          nil
        end

        # ":230 display name normalized to trimmed Unicode NFC with 1-120 scalar
        # values."
        def valid_display_name?(value)
          return false unless value.is_a?(::String)

          normalized = value.unicode_normalize(:nfc).strip
          (1..Platform::BaselineContent::DISPLAY_NAME_MAX).cover?(normalized.length)
        end

        # ---- main branch, under proved principal+Organization context -----------

        def bootstrap(command:, ctx:, store:, organization_id:, receipt:)
          principal_hex = receipt["principal_hex"]
          now = ctx.now_utc.floor(6)
          d = { command:, ctx:, store:, organization_id:, receipt:, principal_hex:, now: }

          store.lock_principal(principal_hex)

          key_digest = Digest::SHA256.digest(command.idempotency_key)
          request_sha256 = request_hash(command, ctx, principal_hex)
          existing = store.find_idempotency(principal_hex:, command_type: command.command_type, key_digest:)
          if existing
            return replay(store, existing, command) if existing["request_hex"] == hex(request_sha256)

            return reject(**d, reason: "idempotency_conflict")
          end

          if (reason = receipt_reason(receipt, now))
            return reject(**d, reason:)
          end

          if store.consumed_grant_exists?
            return reject(**d, reason: "bootstrap_grant_consumed")
          end
          grant = store.issued_grant
          if (reason = grant_reason(grant, principal_hex, command, now))
            return reject(**d, reason:)
          end

          commit(**d, grant:, key_digest:, request_sha256:)
        end

        # ---- the atomic genesis --------------------------------------------------

        def commit(command:, ctx:, store:, organization_id:, receipt:, principal_hex:, now:, grant:, key_digest:, request_sha256:)
          ids = genesis_ids(ctx)
          ids[:organization] = organization_id
          bc = Platform::BaselineContent
          email = receipt_email(receipt)

          write_execution(store, command, ctx, organization_id, principal_hex, ids[:execution], key_digest,
                          request_sha256, now)

          # Normative creation order (:628).
          store.insert_organization(id: organization_id, now:, correlation_id: ctx.correlation_id,
                                    display_name: command.organization_display_name,
                                    profile: profile_document(command),
                                    default_locale: bc::DEFAULT_LOCALE,
                                    reporting_time_zone: bc::REPORTING_TIME_ZONE,
                                    profile_schema_version: bc::PROFILE_SCHEMA_VERSION)
          store.insert_account(id: ids[:account], now:, correlation_id: ctx.correlation_id,
                               organization_id:, issuer_key: receipt["issuer_key"],
                               issuer_subject: receipt["issuer_subject"], normalized_email: email,
                               normalized_email_sha256: Digest::SHA256.digest(email),
                               display_name: command.organization_display_name,
                               receipt_digest: command.receipt_digest)
          store.insert_billing_entity(id: ids[:billing], now:, correlation_id: ctx.correlation_id,
                                      organization_id:,
                                      internal_contract_reference: "f1-billing:#{organization_id}")
          store.insert_admin_assignment(id: ids[:role], now:, correlation_id: ctx.correlation_id,
                                        organization_id:, account_id: ids[:account], scope_sha256: ORG_SCOPE,
                                        allowlist: Platform::PermissionBaseline.protected_permission_preview("OrganizationAdmin"))
          store.insert_access_policy(id: ids[:access_policy], now:, correlation_id: ctx.correlation_id,
                                     organization_id:, semantic_version: bc::ACCESS_POLICY_VERSION,
                                     content_sha256: bc.access_policy_sha256, plan_scope: bc::PLAN_VERSION)
          store.insert_plan_assignment(id: ids[:plan], now:, correlation_id: ctx.correlation_id,
                                       organization_id:, billing_entity_id: ids[:billing],
                                       plan_version: bc::PLAN_VERSION, approval_version: bc::PLAN_APPROVAL_VERSION,
                                       policy_version: bc::ENTITLEMENT_POLICY_VERSION, content_sha256: bc.plan_sha256,
                                       service_identity_id: SERVICE)
          store.insert_entitlement_policy(id: ids[:entitlement_policy], now:, correlation_id: ctx.correlation_id,
                                          organization_id:, semantic_version: bc::ENTITLEMENT_POLICY_VERSION,
                                          plan_version: bc::PLAN_VERSION, content_sha256: bc.entitlement_policy_sha256)
          store.insert_project(id: ids[:project], now:, correlation_id: ctx.correlation_id, organization_id:,
                               display_name: command.project_display_name, locale: bc::DEFAULT_LOCALE,
                               time_zone: bc::REPORTING_TIME_ZONE, objective: command.project_objective)

          # Activations, in order (:628).
          store.activate_billing_entity(ids[:billing], ids[:plan], now)
          store.activate_account(ids[:account], now)
          store.activate_organization(id: organization_id, now:, creator_account_id: ids[:account],
                                      access_policy_id: ids[:access_policy],
                                      entitlement_policy_id: ids[:entitlement_policy],
                                      plan_assignment_id: ids[:plan], billing_entity_id: ids[:billing])

          consume_grant(store, grant, organization_id, command, now)
          nonce = store.consume_nonce(id: ctx.generate_id, now:, receipt_id: receipt["receipt_id"],
                                      receipt_digest: command.receipt_digest,
                                      command_execution_id: ids[:execution], outcome: "consumed", reason_code: nil)
          raise IdentityAccess::Infrastructure::OrganizationGenesisStore::Consumed if nonce == "already_consumed"

          token = create_session(store, ids, organization_id, command, now, ctx)

          payload = success_payload(ids, organization_id)
          audit_id = write_success_audit(store, ids, organization_id, ctx, command, now, payload)
          emit_genesis_events(store, ids, organization_id, ctx, command, now, audit_id, key_digest, request_sha256, grant)
          write_result(store, ids, organization_id, ctx, command, now, payload, audit_id)
          store.insert_idempotency(id: ctx.generate_id, now:, principal_hex:, command_type: command.command_type,
                                   key_digest:, request_sha256:, command_execution_id: ids[:execution],
                                   command_result_id: ids[:result], retain_until: now + (30 * 24 * 3600))

          Platform::CommandResult.success(result_id: ids[:result], command_type: command.command_type,
                                          audit_record_id: audit_id, correlation_id: ctx.correlation_id,
                                          payload: payload.transform_keys(&:to_sym),
                                          session_token: token)
        rescue IdentityAccess::Infrastructure::OrganizationGenesisStore::Consumed
          raise Platform::InvariantViolation, "receipt nonce consumed concurrently"
        rescue LostRace
          raise Platform::InvariantViolation, "bootstrap grant consumed concurrently"
        end

        def consume_grant(store, grant, organization_id, command, now)
          changed = store.consume_grant(grant["id"], grant["state_version"].to_i, organization_id,
                                        command.command_id, now)
          raise LostRace if changed.to_i.zero?

          changed
        end

        # The Session row carries only the digest; the minted pair is returned so the
        # caller can hand the raw token to the transport that sets the cookie. It is
        # never written to the payload, the audit record or an event.
        def create_session(store, ids, organization_id, command, now, ctx)
          token = Platform::SessionToken.mint
          store.insert_session(id: ids[:session], now:, correlation_id: ctx.correlation_id, organization_id:,
                               account_id: ids[:account], identity_receipt_digest: command.receipt_digest,
                               authorization_context_version: 1, creation_reason: "self_service_bootstrap",
                               issued_at: now, last_activity_at: now,
                               idle_expires_at: now + (30 * 60), absolute_expires_at: now + (12 * 3600),
                               token_sha256: token.digest)
          token
        end

        # ":641 self-service event order" — the fixed thirteen, in exactly this
        # sequence. Building them as one ordered list makes the order the code's
        # single source of truth.
        def emit_genesis_events(store, ids, org, ctx, command, now, audit_id, key_digest, request_sha256, grant)
          base = { org:, ctx:, command:, now:, audit_id:, key_digest:, request_sha256:, account_id: ids[:account] }
          # The thirteen occur in sequence within this one transaction. Stamping
          # each at a successive microsecond makes that order a durable, queryable
          # fact rather than relying on uuid tie-breaking under a fixed clock.
          descriptors = [
            event(**base, type: "AccountProvisionRequested", profile: "created", agg: "account",
                  agg_id: ids[:account], version: 0, to: "pending"),
            event(**base, type: "OrganizationCreated", profile: "created", agg: "organization",
                  agg_id: org, version: 0, to: "pending"),
            event(**base, type: "BillingStateChanged", profile: "state_transition", agg: "billing_entity",
                  agg_id: ids[:billing], version: 0, from: nil, to: "pending"),
            event(**base, type: "RoleGranted", profile: "created", agg: "role_assignment",
                  agg_id: ids[:role], version: 0, to: "active"),
            event(**base, type: "AccessPolicyActivated", profile: "policy_activation", agg: "access_policy",
                  agg_id: ids[:access_policy], version: 0),
            event(**base, type: "PlanAssigned", profile: "created", agg: "plan_assignment",
                  agg_id: ids[:plan], version: 0),
            event(**base, type: "EntitlementPolicyActivated", profile: "policy_activation",
                  agg: "entitlement_policy", agg_id: ids[:entitlement_policy], version: 0),
            event(**base, type: "BillingStateChanged", profile: "state_transition", agg: "billing_entity",
                  agg_id: ids[:billing], version: 1, from: "pending", to: "active"),
            event(**base, type: "AccountActivated", profile: "state_transition", agg: "account",
                  agg_id: ids[:account], version: 1, from: "pending", to: "active"),
            event(**base, type: "OrganizationActivated", profile: "state_transition", agg: "organization",
                  agg_id: org, version: 1, from: "pending", to: "active"),
            event(**base, type: "ProjectCreated", profile: "created", agg: "project",
                  agg_id: ids[:project], version: 0, to: "draft"),
            event(**base, type: "BootstrapGrantConsumed", profile: "state_transition", agg: "bootstrap_grant",
                  agg_id: grant["id"], version: 1, from: "issued", to: "consumed"),
            event(**base, type: "SessionCreated", profile: "created", agg: "session",
                  agg_id: ids[:session], version: 0)
          ]
          descriptors.each_with_index do |descriptor, index|
            store.insert_event(**descriptor.call(now + Rational(index, 1_000_000)))
          end
        end

        # Return a builder that stamps the event at `at`, so ordering is decided
        # once, at emission, by the descriptor list above.
        def event(org:, ctx:, command:, now:, audit_id:, key_digest:, request_sha256:, account_id:,
                  type:, profile:, agg:, agg_id:, version:, from: nil, to: nil)
          lambda do |at|
            build_event(org:, ctx:, command:, at:, audit_id:, key_digest:, request_sha256:, account_id:,
                        type:, profile:, agg:, agg_id:, version:, from:, to:)
          end
        end

        def build_event(org:, ctx:, command:, at:, audit_id:, key_digest:, request_sha256:, account_id:,
                        type:, profile:, agg:, agg_id:, version:, from:, to:)
          now = at
          envelope = {
            "account_id" => %w[account role_assignment session].include?(agg) ? account_id : nil,
            "actor_id" => nil, "affected_entity_id" => agg_id, "affected_entity_type" => agg,
            "aggregate_version" => version, "audit_record_id" => audit_id, "causation_id" => ctx.correlation_id,
            "command_id" => command.command_id, "correlation_id" => ctx.correlation_id,
            "event_profile" => profile, "event_type" => type, "from_state" => from,
            "idempotency_identity_hash" => hex(key_digest), "input_hash" => hex(request_sha256),
            "occurred_at_utc" => now.iso8601(6), "organization_id" => org, "outcome" => "success",
            "project_id" => nil, "reason_code" => nil, "schema_version" => "1.0",
            "service_identity_id" => SERVICE, "to_state" => to, "workflow_id" => "WF-001"
          }
          bytes = Platform::CanonicalJson.encode(envelope)
          { id: ctx.generate_id, now:, event_type: type, event_profile: profile, organization_id: org,
            aggregate_type: agg, aggregate_id: agg_id, aggregate_version: version,
            correlation_id: ctx.correlation_id, command_id: command.command_id, audit_record_id: audit_id,
            event_bytes: bytes, event_sha256: Digest::SHA256.digest(bytes) }
        end

        # ---- audited denial (no tenant record) ----------------------------------

        def reject(command:, ctx:, store:, organization_id:, receipt:, principal_hex:, now:, reason:)
          execution_id = ctx.generate_id
          audit_id = ctx.generate_id
          result_id = ctx.generate_id
          key_digest = Digest::SHA256.digest(command.idempotency_key)
          request_sha256 = request_hash(command, ctx, principal_hex)

          write_execution(store, command, ctx, organization_id, principal_hex, execution_id, key_digest,
                          request_sha256, now)
          store.insert_audit(id: audit_id, now:, organization_id:, service_identity_id: SERVICE,
                             correlation_id: ctx.correlation_id, command_id: command.command_id,
                             entity_type: "organization", entity_id: organization_id, to_state: nil,
                             outcome: "failure", reason_code: reason,
                             payload: JSON.generate({ "branch" => "self_service_bootstrap", "rejected" => reason }),
                             content_sha256: Platform::CanonicalJson.digest({ "rejected" => reason }))
          failure = Platform::ErrorCatalog.failure(reason, support_reference: ctx.correlation_id)
          write_result(store, { execution: execution_id, result: result_id }, organization_id, ctx, command,
                       now, {}, audit_id, failure:)
          unless reason == "idempotency_conflict"
            store.insert_idempotency(id: ctx.generate_id, now:, principal_hex:, command_type: command.command_type,
                                     key_digest:, request_sha256:, command_execution_id: execution_id,
                                     command_result_id: result_id, retain_until: now + (30 * 24 * 3600))
          end
          Platform::CommandResult.failure(result_id:, command_type: command.command_type, failure:,
                                          audit_record_id: audit_id, correlation_id: ctx.correlation_id)
        end

        def replay(store, existing, command)
          stored = store.load_command_result(existing["command_result_id"])
          if stored["outcome"] == "success"
            Platform::CommandResult.success(result_id: stored["id"], command_type: command.command_type,
                                            payload: JSON.parse(stored["authorized_payload"]).transform_keys(&:to_sym),
                                            audit_record_id: stored["audit_record_id"],
                                            correlation_id: stored["correlation_id"], replayed: true)
          else
            failure = Platform::Failure.new(
              error_class: stored["error_class"], error_code: stored["error_code"],
              reason_code: stored["reason_code"], severity: stored["severity"],
              retryable: stored["retryable"] == "t" || stored["retryable"] == true,
              recovery_action: stored["recovery_action"], support_reference: stored["support_reference"]
            )
            Platform::CommandResult.failure(result_id: stored["id"], command_type: command.command_type,
                                            failure:, audit_record_id: stored["audit_record_id"],
                                            correlation_id: stored["correlation_id"], replayed: true)
          end
        end

        # ---- ledger writers ------------------------------------------------------

        def write_execution(store, command, ctx, org, principal_hex, id, key_digest, request_sha256, now)
          store.insert_command_execution(
            id:, now:, correlation_id: ctx.correlation_id, command_id: command.command_id,
            key_digest:, command_type: command.command_type, command_schema_version: command.schema_version,
            service_identity_id: SERVICE, organization_id: org, principal_hex:, action: ACTION,
            requested_at: command.requested_at_utc, policy_versions: policy_versions_json,
            canonical_payload: canonical_payload_json(command), request_sha256:
          )
        end

        def write_success_audit(store, ids, org, ctx, command, now, payload)
          audit_id = ids[:audit]
          store.insert_audit(id: audit_id, now:, organization_id: org, service_identity_id: SERVICE,
                             correlation_id: ctx.correlation_id, command_id: command.command_id,
                             entity_type: "organization", entity_id: org, to_state: "active", outcome: "success",
                             reason_code: nil, payload: JSON.generate(payload.merge("branch" => "self_service_bootstrap")),
                             content_sha256: Platform::CanonicalJson.digest(payload))
          audit_id
        end

        def write_result(store, ids, org, ctx, command, now, payload, audit_id, failure: nil)
          store.insert_command_result(
            id: ids[:result], now:, correlation_id: ctx.correlation_id, command_id: command.command_id,
            command_execution_id: ids[:execution], outcome: failure ? "failure" : "success", organization_id: org,
            service_identity_id: SERVICE,
            target_refs: JSON.generate(failure ? {} : { "organization" => org }),
            governing_policy_versions: policy_versions_json, failure:,
            authorized_payload: JSON.generate(failure ? {} : payload), audit_record_id: audit_id
          )
        end

        # ---- validation helpers --------------------------------------------------

        def receipt_reason(receipt, now)
          return "identity_issuer_unsupported" unless APPROVED_ISSUERS.include?(receipt["issuer_key"])
          return "identity_schema_unsupported" unless receipt["receipt_schema_version"] == "onboarding-interim-v1"
          return "identity_receipt_purpose_mismatch" unless receipt["purpose"] == RECEIPT_PURPOSE
          return "identity_email_unverified" unless truthy(receipt["email_verified"])
          return "identity_receipt_expired" if now >= to_time(receipt["expires_at"])

          nil
        end

        def grant_reason(grant, principal_hex, command, now)
          return "bootstrap_grant_unavailable" if grant.nil?
          return "bootstrap_grant_unavailable" unless grant["principal_hex"] == principal_hex
          return "stale_state_version" unless command.expected_grant_version == grant["state_version"].to_i
          return "bootstrap_grant_expired" if now >= to_time(grant["expires_at"])

          nil
        end

        # ---- shapes --------------------------------------------------------------

        def profile_document(command)
          { "display_name" => command.organization_display_name.unicode_normalize(:nfc).strip,
            "default_locale" => Platform::BaselineContent::DEFAULT_LOCALE,
            "reporting_time_zone" => Platform::BaselineContent::REPORTING_TIME_ZONE,
            "organization_profile_schema_version" => Platform::BaselineContent::PROFILE_SCHEMA_VERSION }
        end

        def success_payload(ids, organization_id)
          { "organization_id" => organization_id, "status" => "active", "account_id" => ids[:account],
            "billing_entity_id" => ids[:billing], "role_assignment_id" => ids[:role],
            "access_policy_id" => ids[:access_policy], "entitlement_policy_id" => ids[:entitlement_policy],
            "plan_assignment_id" => ids[:plan], "project_id" => ids[:project], "session_id" => ids[:session],
            "authorization_epoch" => 1 }
        end

        def genesis_ids(ctx)
          %i[execution audit result account billing role access_policy entitlement_policy plan project session]
            .to_h { |k| [k, ctx.generate_id] }
        end

        def receipt_email(receipt) = receipt["normalized_email"] || "user-#{receipt["receipt_id"]}@example.com"

        def request_hash(command, ctx, principal_hex)
          Platform::CanonicalJson.digest({
            "action" => ACTION, "bootstrap_principal" => principal_hex,
            "command_schema_version" => command.schema_version, "command_type" => command.command_type,
            "expected_grant_version" => command.expected_grant_version,
            "policy_versions" => [POLICY_VERSION], "service_identity_id" => SERVICE,
            "command_payload" => {
              "organization_display_name" => command.organization_display_name.to_s.unicode_normalize(:nfc).strip,
              "project_display_name" => command.project_display_name.to_s.unicode_normalize(:nfc).strip,
              "access_policy_content" => hex(command.access_policy_content_sha256),
              "entitlement_policy_content" => hex(command.entitlement_policy_content_sha256),
              "plan_content" => hex(command.plan_content_sha256)
            }
          })
        end

        def schema_failure(command, ctx) = in_memory_failure(command, ctx, "command_schema_unsupported")

        def in_memory_failure(command, ctx, reason)
          failure = Platform::ErrorCatalog.failure(reason, support_reference: ctx.correlation_id)
          Platform::CommandResult.failure(result_id: ctx.generate_id, command_type: command.command_type,
                                          failure:, audit_record_id: ctx.generate_id,
                                          correlation_id: ctx.correlation_id)
        end

        def supported_schema?(version) = version.to_s.split(".").first == SUPPORTED_SCHEMA_MAJOR
        def policy_versions_json = JSON.generate({ "onboarding" => POLICY_VERSION })
        def canonical_payload_json(command) = JSON.generate({ "organization_display_name" => command.organization_display_name.to_s.unicode_normalize(:nfc).strip })
        def truthy(value) = value == true || value == "t"
        def to_time(value) = value.respond_to?(:getutc) ? value.getutc : Time.parse(value).getutc
        def hex(bytes) = bytes.unpack1("H*")

        class LostRace < StandardError; end
      end
    end
  end
end
