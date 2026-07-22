# frozen_string_literal: true

require "rails_helper"

# The Role Assignment invariants, each asserted at the strongest layer that can
# actually hold it.
#
# The ordering principle throughout: if the database can refuse it, the database
# refuses it and the assertion is made against the raw owner connection, not
# against the application. An invariant proved only by "the handler declines to
# try" is not an invariant — it is a convention that survives exactly as long as
# the next handler remembers it.
RSpec.describe "WF-013 role assignment invariants", type: :acceptance,
               acceptance_ids: ["AC-CAP-013", "AC-CAP-025", "AC-WF-013"],
               test_types: %w[TYP-SEC TYP-DATA TYP-INT] do
  self.use_transactional_tests = false

  after { ReceiptMinter.truncate_all }

  def t0 = Time.utc(2026, 6, 1, 10, 0, 0)
  def t1 = t0 + (10 * 24 * 3600)
  def org_scope = Digest::SHA256.digest("scope:organization")

  let(:admin) { TenantSeeder.seed_authorized_admin(issued_at: t0 - 900) }
  let(:org) { admin[:organization_id] }

  def owner = DbInspector.connection

  def ctx(now = t0)
    Platform::RequestContext.for_actor(clock: Platform::Clock.fixed(now), ids: Platform::Ids.system,
                                       correlation_id: SecureRandom.uuid_v7)
  end

  def account(subject = "person")
    TenantSeeder.create_account(organization_id: org, issuer_key: "https://id.example/oidc",
                                subject: "#{subject}-#{SecureRandom.hex(6)}")
  end

  def session_for(account_id, at: t0)
    TenantSeeder.create_session(organization_id: org, account_id:, issued_at: at - 900,
                                last_activity_at: at)
  end

  def grant(target: nil, role: "MarketingOperator", expires_at: nil, epoch: 7,
            key: "g-#{SecureRandom.hex(3)}", session_id: nil, at: t0)
    cmd = Workflows::Wf013::Commands::RequestRoleAssignment.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0",
      session_id: session_id || admin[:session_id], account_id: target || account,
      canonical_role: role, permission_mode: "standard", persona: nil, scope_sha256: org_scope,
      expires_at:, expected_authorization_epoch: epoch, reason: nil, requested_at_utc: at
    )
    Workflows::Wf013::Handlers::RequestRoleAssignment.new.call(command: cmd, request_context: ctx(at))
  end

  def decide(id, session_id, decision: "approve", version: 0, epoch: 7, reason: nil,
             key: "d-#{SecureRandom.hex(3)}", at: t0)
    cmd = Workflows::Wf013::Commands::DecideRoleAssignment.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0", session_id:,
      role_assignment_id: id, expected_state_version: version, expected_authorization_epoch: epoch,
      decision:, reason:, requested_at_utc: at
    )
    Workflows::Wf013::Handlers::DecideRoleAssignment.new.call(command: cmd, request_context: ctx(at))
  end

  def revoke(id, session_id:, version: 0, epoch: 8, key: "r-#{SecureRandom.hex(3)}", at: t0)
    cmd = Workflows::Wf013::Commands::RevokeRoleAssignment.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0", session_id:,
      role_assignment_id: id, expected_state_version: version, expected_authorization_epoch: epoch,
      reason: "revoked for the invariant assertion set", requested_at_utc: at
    )
    Workflows::Wf013::Handlers::RevokeRoleAssignment.new.call(command: cmd, request_context: ctx(at))
  end

  def worker(now = t1)
    Platform::ScheduledActions::Worker.new(
      registry: Platform::ScheduledActions::Registry.default,
      scheduler: Platform::ScheduledActions::Scheduler.new,
      clock: Platform::Clock.fixed(now), ids: Platform::Ids.system
    )
  end

  def security_operator(at: t0, expires_at: nil)
    id = account("sec")
    assignment = TenantSeeder.create_role_assignment(
      organization_id: org, account_id: id, canonical_role: "SecurityOperator",
      scope_sha256: org_scope, effective_at: t0, expires_at:,
      protected_permission_allowlist: Platform::PermissionBaseline.protected_permission_preview("SecurityOperator")
    )
    { account_id: id, assignment_id: assignment, session_id: session_for(id, at:) }
  end

  def assignment(id) = DbInspector.one("SELECT * FROM role_assignments WHERE id = $1::uuid", [id])
  def epoch = DbInspector.one("SELECT authorization_epoch FROM organizations WHERE id = $1::uuid",
                              [org])["authorization_epoch"].to_i

  # A raw owner-side UPDATE, so what is being proved is the database boundary and
  # not the application's restraint.
  def owner_update(sql, params)
    owner.exec_params(sql, params)
  end

  # ===========================================================================
  describe "state and transitions" do
    it "closes the status vocabulary at the database" do
      # Asserted at INSERT, where the CHECK is the only thing standing between the
      # value and the table: the UPDATE path also has the transition guard, which
      # would mask a widened vocabulary.
      %w[suspended expiry_blocked_last_admin].each do |invalid|
        expect { insert_assignment(status: invalid) }.to raise_error(PG::CheckViolation)
      end

      vocabulary = owner.exec(<<~SQL).getvalue(0, 0)
        SELECT pg_get_constraintdef(oid) FROM pg_constraint
        WHERE conrelid = 'role_assignments'::regclass AND conname LIKE '%status%'
      SQL
      %w[pending active rejected revoked expired].each { |s| expect(vocabulary).to include("'#{s}'") }
    end

    # A raw INSERT, so a CHECK is proved by the CHECK.
    def insert_assignment(status:, account_id: nil)
      params = [SecureRandom.uuid_v7, org, account_id || account("raw"), status, t0.iso8601(6)]
      owner.exec_params(<<~SQL, params)
        INSERT INTO role_assignments
          (id, state_version, lock_version, created_at, updated_at, correlation_id, organization_id,
           account_id, canonical_role, permission_mode, status, effective_at, protected_permission_allowlist)
        VALUES ($1,0,0,now(),now(),gen_random_uuid(),$2::uuid,$3::uuid,'MarketingOperator','standard',
                $4,$5::timestamptz,'[]'::jsonb)
      SQL
    end

    it "closes the permitted transition table at the database" do
      id = grant.payload[:role_assignment_id]
      # active -> pending and active -> rejected are not in the ratified table.
      expect { owner_update("UPDATE role_assignments SET status = 'pending' WHERE id = $1::uuid", [id]) }
        .to raise_error(PG::RaiseException, /role_assignment_illegal_transition/)
      expect { owner_update("UPDATE role_assignments SET status = 'rejected' WHERE id = $1::uuid", [id]) }
        .to raise_error(PG::RaiseException, /role_assignment_illegal_transition/)
    end

    %w[revoked expired rejected].each do |terminal|
      it "makes #{terminal} terminal" do
        id = TenantSeeder.create_role_assignment(
          organization_id: org, account_id: account("held"), canonical_role: "MarketingOperator",
          scope_sha256: org_scope, status: terminal, effective_at: t0
        )

        %w[active pending expired revoked rejected].reject { |s| s == terminal }.each do |target|
          expect { owner_update("UPDATE role_assignments SET status = $2 WHERE id = $1::uuid", [id, target]) }
            .to raise_error(PG::RaiseException, /role_assignment_illegal_transition/),
                "#{terminal} -> #{target} was permitted"
        end
      end
    end

    it "confers nothing while pending" do
      security = security_operator
      pending = grant(role: "SecurityOperator", expires_at: t1)
      id = pending.payload[:role_assignment_id]
      holder_session = session_for(assignment(id)["account_id"])

      expect(assignment(id)["status"]).to eq("pending")
      expect(authorizes?(holder_session, "invitation.approve")).to be(false)

      expect(decide(id, security[:session_id])).to be_success
      expect(authorizes?(session_for(assignment(id)["account_id"]), "invitation.approve")).to be(true)
    end

    it "confers nothing in any inactive state" do
      %w[rejected revoked expired].each do |terminal|
        target = account("holder-#{terminal}")
        id = TenantSeeder.create_role_assignment(
          organization_id: org, account_id: target, canonical_role: "OrganizationAdmin",
          scope_sha256: org_scope, status: terminal, effective_at: t0,
          protected_permission_allowlist: Platform::PermissionBaseline.protected_permission_preview("OrganizationAdmin")
        )
        expect(assignment(id)["status"]).to eq(terminal)
        expect(authorizes?(session_for(target), "role.manage")).to be(false)
      end
    end

    # Run the real effective-permission checkpoint for one Session.
    def authorizes?(session_id, capability)
      Platform::UnitOfWork.run do |conn|
        store = IdentityAccess::Infrastructure::AuthorizationStore.new(conn.raw_connection)
        auth = IdentityAccess::Authorization::CommandAuthorizer.new(store)
        actor = auth.authenticate(session_id:, now: t0, correlation_id: SecureRandom.uuid_v7)
        next false if actor.is_a?(Symbol)

        auth.authorize(actor:, capability:, now: t0).allowed?
      end
    end
  end

  # ===========================================================================
  describe "historical integrity" do
    def approved_protected
      security = security_operator
      pending = grant(role: "SecurityOperator", expires_at: t1)
      id = pending.payload[:role_assignment_id]
      expect(decide(id, security[:session_id])).to be_success
      { id:, security: }
    end

    {
      "canonical_role" => "'OrganizationAdmin'",
      "scope_sha256" => "decode('00','hex')",
      "requester_account_id" => "gen_random_uuid()",
      "permission_mode" => "'read_only'",
      "account_id" => "gen_random_uuid()",
      "organization_id" => "gen_random_uuid()",
      "requested_at" => "now()"
    }.each do |column, value|
      it "refuses any change to #{column} after the grant exists" do
        id = grant.payload[:role_assignment_id]
        expect { owner_update("UPDATE role_assignments SET #{column} = #{value} WHERE id = $1::uuid", [id]) }
          .to raise_error(PG::RaiseException, /role_assignment_grant_content_immutable/)
      end
    end

    it "makes approval records append-only for the runtime" do
      subject = approved_protected
      expect(DbInspector.one("SELECT has_table_privilege('f1_web','role_assignment_approvals','UPDATE') AS p")["p"])
        .to eq("f")
      expect(DbInspector.one("SELECT has_table_privilege('f1_web','role_assignment_approvals','DELETE') AS p")["p"])
        .to eq("f")
      expect(DbInspector.count("role_assignment_approvals")).to eq(1)
      expect(subject[:id]).not_to be_nil
    end

    it "makes duplicate approvers impossible" do
      subject = approved_protected
      approval = DbInspector.one("SELECT * FROM role_assignment_approvals")

      expect do
        owner.exec_params(<<~SQL, [SecureRandom.uuid_v7, org, subject[:id], approval["approver_account_id"]])
          INSERT INTO role_assignment_approvals
            (id, schema_version, created_at, organization_id, role_assignment_id, sequence_number,
             approver_account_id, authority, decision, decided_at, policy_version, separation_result,
             correlation_id)
          VALUES ($1,'1.0',now(),$2::uuid,$3::uuid,2,$4::uuid,'SecurityOperator','approve',now(),
                  'permission-baseline-v1','distinct',gen_random_uuid())
        SQL
      end.to raise_error(PG::UniqueViolation, /one_approval_per_approver/)
    end

    it "keeps approval sequence numbers ordered and unique" do
      subject = approved_protected
      expect do
        owner.exec_params(<<~SQL, [SecureRandom.uuid_v7, org, subject[:id]])
          INSERT INTO role_assignment_approvals
            (id, schema_version, created_at, organization_id, role_assignment_id, sequence_number,
             approver_account_id, authority, decision, decided_at, policy_version, separation_result,
             correlation_id)
          VALUES ($1,'1.0',now(),$2::uuid,$3::uuid,1,gen_random_uuid(),'SecurityOperator','approve',now(),
                  'permission-baseline-v1','distinct',gen_random_uuid())
        SQL
      end.to raise_error(PG::UniqueViolation, /approval_records_are_ordered/)
    end

    it "writes the protected allowlist only on the canonical activation edge" do
      pending = grant(role: "SecurityOperator", expires_at: t1)
      id = pending.payload[:role_assignment_id]
      # While pending, not even the owner may put authority in it.
      expect do
        owner_update(<<~SQL, [id])
          UPDATE role_assignments SET protected_permission_allowlist = '["invitation.approve"]'::jsonb
          WHERE id = $1::uuid
        SQL
      end.to raise_error(PG::RaiseException, /role_assignment_allowlist_immutable/)

      security = security_operator
      expect(decide(id, security[:session_id])).to be_success
      expect(JSON.parse(assignment(id)["protected_permission_allowlist"])).to include("invitation.approve")
    end

    it "refuses any later change to the allowlist" do
      subject = approved_protected
      expect do
        owner_update("UPDATE role_assignments SET protected_permission_allowlist = '[]'::jsonb WHERE id = $1::uuid",
                     [subject[:id]])
      end.to raise_error(PG::RaiseException, /role_assignment_allowlist_immutable/)
      expect do
        owner_update(<<~SQL, [subject[:id]])
          UPDATE role_assignments
          SET protected_permission_allowlist = protected_permission_allowlist || '["account.delete"]'::jsonb
          WHERE id = $1::uuid
        SQL
      end.to raise_error(PG::RaiseException, /role_assignment_allowlist_immutable/)
    end

    it "does not erase approval history on revocation" do
      subject = approved_protected
      revoker = security_operator
      before = DbInspector.all("SELECT * FROM role_assignment_approvals ORDER BY sequence_number")

      expect(revoke(subject[:id], session_id: revoker[:session_id], version: 1)).to be_success
      after = DbInspector.all("SELECT * FROM role_assignment_approvals ORDER BY sequence_number")
      expect(after).to eq(before)
      expect(JSON.parse(assignment(subject[:id])["protected_permission_allowlist"])).not_to be_empty
    end

    it "does not erase approval history on expiry" do
      subject = approved_protected
      before = DbInspector.all("SELECT * FROM role_assignment_approvals ORDER BY sequence_number")

      expect(worker.run_due_batch.map(&:disposition)).to eq([:completed])
      expect(assignment(subject[:id])["status"]).to eq("expired")
      expect(DbInspector.all("SELECT * FROM role_assignment_approvals ORDER BY sequence_number")).to eq(before)
      expect(JSON.parse(assignment(subject[:id])["protected_permission_allowlist"])).not_to be_empty
    end

    it "keeps historical RoleExpiryBlockDecisions queryable and unalterable" do
      id = sole_admin_with_timer
      expect(worker.run_due_batch.map(&:disposition)).to eq([:completed])

      decision = DbInspector.one("SELECT * FROM role_expiry_block_decisions")
      expect(decision["block_reason"]).to eq("expiry_blocked_last_admin")
      expect(decision["retention_class"]).to eq("security_audit")
      %w[UPDATE DELETE].each do |privilege|
        expect(DbInspector.one("SELECT has_table_privilege('f1_web','role_expiry_block_decisions','#{privilege}') AS p")["p"])
          .to eq("f")
      end
      # Still readable after the Assignment moves on.
      expect(assignment(id)["status"]).to eq("active")
      expect(DbInspector.count("role_expiry_block_decisions")).to eq(1)
    end
  end

  # ===========================================================================
  describe "time and scheduling" do
    it "refuses an invalid effective interval" do
      id = grant.payload[:role_assignment_id]
      expect { owner_update("UPDATE role_assignments SET effective_at = NULL WHERE id = $1::uuid", [id]) }
        .to raise_error(PG::CheckViolation, /role_assignment_active_is_effective/)

      pending = grant(role: "OrganizationAdmin", expires_at: t1, epoch: 8).payload[:role_assignment_id]
      expect { owner_update("UPDATE role_assignments SET effective_at = now() WHERE id = $1::uuid", [pending]) }
        .to raise_error(PG::CheckViolation, /role_assignment_pending_is_not_effective/)
    end

    it "holds a protected Assignment to the canonical 30-day maximum" do
      # The command refuses it …
      expect(grant(role: "OrganizationAdmin", expires_at: t0 + (31 * 24 * 3600)).reason_code)
        .to eq("role_expiry_invalid")
      expect(grant(role: "OrganizationAdmin", expires_at: nil).reason_code).to eq("role_expiry_required")

      # … and so does the database, for an Assignment carrying protected authority.
      target = account("beyond")
      expect do
        owner.exec_params(<<~SQL, [SecureRandom.uuid_v7, org, target, t0.iso8601(6), (t0 + (31 * 24 * 3600)).iso8601(6)])
          INSERT INTO role_assignments
            (id, state_version, lock_version, created_at, updated_at, correlation_id, organization_id,
             account_id, canonical_role, permission_mode, status, effective_at, expires_at,
             protected_permission_allowlist)
          VALUES ($1,0,0,now(),now(),gen_random_uuid(),$2::uuid,$3::uuid,'OrganizationAdmin','standard',
                  'active',$4::timestamptz,$5::timestamptz,'["role.manage"]'::jsonb)
        SQL
      end.to raise_error(PG::CheckViolation, /role_assignment_protected_expiry_within_30_days/)
    end

    it "gives an active expiring Assignment exactly one timer" do
      grant(expires_at: t1)
      grant(key: "second", epoch: 8, expires_at: t1)

      expect(DbInspector.count("scheduled_actions")).to eq(2)
      expect(DbInspector.all(<<~SQL)).to be_empty
        SELECT r.id FROM role_assignments r
        WHERE r.status = 'active' AND r.expires_at IS NOT NULL
          AND (SELECT count(*) FROM scheduled_actions a
               WHERE a.target_id = r.id AND a.action_kind = 'role_assignment_expire') <> 1
      SQL
    end

    it "gives pending and rejected Assignments none" do
      security = security_operator
      pending = grant(role: "OrganizationAdmin", expires_at: t1).payload[:role_assignment_id]
      expect(DbInspector.count("scheduled_actions")).to eq(0)

      expect(decide(pending, security[:session_id], decision: "reject",
                    reason: "rejected for the invariant assertion set")).to be_success
      expect(assignment(pending)["status"]).to eq("rejected")
      expect(DbInspector.count("scheduled_actions")).to eq(0)
    end

    it "points every timer at exactly one Assignment in the same Organization" do
      grant(expires_at: t1)
      grant(key: "second", epoch: 8, expires_at: t1)

      mismatched = DbInspector.all(<<~SQL)
        SELECT a.id FROM scheduled_actions a
        WHERE a.action_kind = 'role_assignment_expire'
          AND (a.target_type <> 'role_assignment'
               OR (SELECT count(*) FROM role_assignments r
                   WHERE r.id = a.target_id AND r.organization_id = a.organization_id) <> 1)
      SQL
      expect(mismatched).to be_empty
    end

    it "maps the timer purpose to exactly one production handler" do
      registry = Platform::ScheduledActions::Registry.default
      entry = registry.resolve(action_kind: "role_assignment_expire", action_schema_version: "1.0")

      expect(entry).not_to be_nil
      expect(entry.handler).to eq(Workflows::Wf013::Handlers::ExpireRoleAssignment)
      expect(entry.command).to eq(Workflows::Wf013::Commands::ExpireRoleAssignment)
      expect(entry.operation).to eq("ExpireRoleAssignment")
    end

    it "never lets a valid due role_assignment_expire action reach a mapping mismatch" do
      grant(expires_at: t1)
      outcomes = worker.run_due_batch

      expect(outcomes.map(&:reason)).not_to include("scheduled_work_mapping_mismatch")
      expect(DbInspector.all("SELECT status, reason FROM scheduled_actions").map { |a| a["status"] })
        .to eq(["completed"])
    end

    it "fails closed on an unknown catalogue kind" do
      registry = Platform::ScheduledActions::Registry.default
      expect(registry.resolve(action_kind: "session_expire", action_schema_version: "1.0")).to be_nil
      expect(registry.resolve(action_kind: "role_assignment_expire", action_schema_version: "2.0")).to be_nil
      # An action kind outside the ratified catalogue cannot even be registered.
      expect { registry.register(action_kind: "not_a_real_kind", action_schema_version: "1.0",
                                 operation: "X", handler: Object, command: Object) }
        .to raise_error(Platform::ScheduledActions::Registry::UnknownActionKind)
    end
  end

  # ===========================================================================
  describe "epoch and authority" do
    it "refuses an owner-side decrease of the authorization epoch" do
      expect do
        owner_update("UPDATE organizations SET authorization_epoch = authorization_epoch - 1 WHERE id = $1::uuid",
                     [org])
      end.to raise_error(PG::RaiseException, /organization_authorization_epoch_regressed/)
    end

    it "advances the epoch atomically with activation, revoke and successful expiry" do
      security = security_operator
      revoker = security_operator

      before = epoch
      pending = grant(role: "SecurityOperator", expires_at: t1).payload[:role_assignment_id]
      expect(epoch).to eq(before) # a pending protected grant changes no authority

      expect(decide(pending, security[:session_id])).to be_success
      expect(epoch).to eq(before + 1)

      direct = grant(key: "direct", epoch: before + 1).payload[:role_assignment_id]
      expect(epoch).to eq(before + 2)

      expect(revoke(direct, session_id: revoker[:session_id], epoch: before + 2)).to be_success
      expect(epoch).to eq(before + 3)

      expect(worker.run_due_batch.map(&:disposition)).to eq([:completed]) # the surviving timer
      expect(assignment(pending)["status"]).to eq("expired")
      expect(epoch).to eq(before + 4)
    end

    it "does not advance the epoch on a blocked expiry" do
      sole_admin_with_timer
      before = epoch

      expect(worker.run_due_batch.map(&:disposition)).to eq([:completed])
      expect(DbInspector.count("role_expiry_block_decisions")).to eq(1)
      expect(epoch).to eq(before)
    end

    it "does not advance the epoch twice on replay" do
      id = grant(expires_at: t1).payload[:role_assignment_id]
      revoker = security_operator
      first = revoke(id, session_id: revoker[:session_id], key: "same")
      expect(first).to be_success
      after_first = epoch

      replay = revoke(id, session_id: revoker[:session_id], key: "same")
      expect(replay.replayed).to be(true)
      expect(epoch).to eq(after_first)
    end

    it "refuses a stale Session after revoke and after expiry" do
      revoker = security_operator
      holder = account("holder")
      revoked_assignment = grant(target: holder, role: "MarketingOperator").payload[:role_assignment_id]
      holder_session = session_for(holder)
      expect(revoke(revoked_assignment, session_id: revoker[:session_id])).to be_success
      expect(authorizes_for?(holder_session, "invitation.create")).to be(false)

      expiring = account("expiring")
      TenantSeeder.create_role_assignment(organization_id: org, account_id: expiring,
                                          canonical_role: "OrganizationAdmin", scope_sha256: org_scope,
                                          effective_at: t0, expires_at: t1,
                                          protected_permission_allowlist: ["role.manage"])
      expect(authorizes_for?(session_for(expiring, at: t1 - 1), "role.manage", now: t1 - 1)).to be(true)
      expect(authorizes_for?(session_for(expiring, at: t1), "role.manage", now: t1)).to be(false)
    end

    it "does not let a stale authorization decision authorize a later command" do
      # An OrganizationAdmin, because `invitation.create` is an OrganizationAdmin
      # cell. It is arranged with the allowlist an approval would have written.
      holder = account("holder")
      id = TenantSeeder.create_role_assignment(
        organization_id: org, account_id: holder, canonical_role: "OrganizationAdmin",
        scope_sha256: org_scope, effective_at: t0,
        protected_permission_allowlist: Platform::PermissionBaseline.protected_permission_preview("OrganizationAdmin")
      )
      holder_session = session_for(holder)
      expect(create_invitation(holder_session)).to be_success

      recorded = DbInspector.all("SELECT * FROM authorization_decisions ORDER BY created_at").last
      expect(recorded["decision"]).to eq("allow")

      revoker = security_operator
      expect(revoke(id, session_id: revoker[:session_id], epoch: 7)).to be_success

      # The stored allow is history, not a credential: the next command
      # re-evaluates and is refused.
      expect(create_invitation(holder_session, key: "after").reason_code).to eq("missing_authority")
      expect(DbInspector.all("SELECT decision FROM authorization_decisions ORDER BY created_at").last["decision"])
        .to eq("deny")
    end

    it "does not let one idempotency key bridge materially different epochs" do
      id = grant(expires_at: t1).payload[:role_assignment_id]
      revoker = security_operator
      expect(revoke(id, session_id: revoker[:session_id], key: "shared")).to be_success

      second = grant(key: "another", epoch: 9).payload[:role_assignment_id]
      conflicting = revoke(second, session_id: revoker[:session_id], key: "shared", epoch: 10)

      # A different target with the same key is a different idempotency scope, so
      # this succeeds; what must NOT happen is the first result being replayed for
      # the second target.
      expect(conflicting.payload[:role_assignment_id]).to eq(second)

      # The same target under a different quoted epoch is an altered command.
      third = revoke(id, session_id: revoker[:session_id], key: "shared", epoch: 11, version: 1)
      expect(third.reason_code).to eq("idempotency_conflict")
    end

    def authorizes_for?(session_id, capability, now: t0)
      Platform::UnitOfWork.run do |conn|
        store = IdentityAccess::Infrastructure::AuthorizationStore.new(conn.raw_connection)
        auth = IdentityAccess::Authorization::CommandAuthorizer.new(store)
        actor = auth.authenticate(session_id:, now:, correlation_id: SecureRandom.uuid_v7)
        next false if actor.is_a?(Symbol)

        auth.authorize(actor:, capability:, now:).allowed?
      end
    end

    def create_invitation(session_id, key: "inv-#{SecureRandom.hex(3)}")
      cmd = Workflows::Wf013::Commands::CreateInvitation.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0", session_id:,
        target_email: "invitee-#{SecureRandom.hex(4)}@example.com", target_identity_issuer_key: nil,
        target_identity_subject: nil, canonical_role: "MarketingOperator", permission_mode: "standard",
        persona: nil, scope_sha256: org_scope, intended_assignment_expires_at: nil, requested_at_utc: t0
      )
      Workflows::Wf013::Handlers::CreateInvitation.new.call(command: cmd, request_context: ctx)
    end
  end

  # ===========================================================================
  describe "attribution and isolation" do
    it "attributes Request, Decide and Revoke to the human actor with a null Service Identity" do
      security = security_operator
      revoker = security_operator
      pending = grant(role: "SecurityOperator", expires_at: t1).payload[:role_assignment_id]
      decide(pending, security[:session_id])
      revoke(pending, session_id: revoker[:session_id], version: 1)

      rows = DbInspector.all(<<~SQL)
        SELECT command_type, actor_id, service_identity_id FROM command_executions ORDER BY created_at
      SQL
      expect(rows.map { |r| r["command_type"] }).to eq(%w[wf013.request_role_assignment
                                                          wf013.decide_role_assignment
                                                          wf013.revoke_role_assignment])
      rows.each do |row|
        expect(row["actor_id"]).not_to be_nil
        expect(row["service_identity_id"]).to be_nil
      end
    end

    it "attributes ExpireRoleAssignment to the Service Identity with a null actor" do
      grant(expires_at: t1)
      worker.run_due_batch

      row = DbInspector.all("SELECT * FROM command_executions ORDER BY created_at").last
      expect(row["command_type"]).to eq("wf013.expire_role_assignment")
      expect(row["service_identity_id"]).to eq(Platform::ServiceIdentity.scheduled_action_executor)
      expect(row["actor_id"]).to be_nil

      audit = DbInspector.all("SELECT * FROM audit_record_registry ORDER BY created_at").last
      expect(audit["service_identity_id"]).to eq(Platform::ServiceIdentity.scheduled_action_executor)
      expect(audit["actor_id"]).to be_nil
    end

    it "gives RoleExpiryBlocked the canonical decision attribution profile" do
      sole_admin_with_timer
      worker.run_due_batch

      body = JSON.parse(DbInspector.one(<<~SQL)["b"])
        SELECT convert_from(event_bytes,'UTF8') AS b FROM event_registry WHERE event_type = 'RoleExpiryBlocked'
      SQL
      expect(body["event_profile"]).to eq("decision")
      expect(body["affected_entity_type"]).to eq("role_expiry_block_decision")
      expect(body["service_identity_id"]).to eq(Platform::ServiceIdentity.scheduled_action_executor)
      expect(body["actor_id"]).to be_nil
      expect(body["account_id"]).to be_nil
    end

    it "never substitutes a Service Identity for a human actor, in either direction" do
      security = security_operator
      pending = grant(role: "SecurityOperator", expires_at: t1).payload[:role_assignment_id]
      decide(pending, security[:session_id])
      worker.run_due_batch

      violations = DbInspector.all(<<~SQL)
        SELECT id FROM command_executions
        WHERE (actor_id IS NULL) = (service_identity_id IS NULL)
        UNION ALL
        SELECT id FROM command_results WHERE (actor_id IS NULL) = (service_identity_id IS NULL)
        UNION ALL
        SELECT id FROM audit_record_registry WHERE (actor_id IS NULL) = (service_identity_id IS NULL)
      SQL
      expect(violations).to be_empty
    end

    it "keeps every actor and Service Identity reference valid" do
      security = security_operator
      pending = grant(role: "SecurityOperator", expires_at: t1).payload[:role_assignment_id]
      decide(pending, security[:session_id])
      worker.run_due_batch

      dangling = DbInspector.all(<<~SQL)
        SELECT e.id FROM command_executions e
        WHERE (e.actor_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM accounts a WHERE a.id = e.actor_id))
           OR (e.service_identity_id IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM service_identities s WHERE s.id = e.service_identity_id))
      SQL
      expect(dangling).to be_empty
    end

    it "keeps row level security forced on every Role Assignment table" do
      forced = DbInspector.all(<<~SQL)
        SELECT relname, relrowsecurity, relforcerowsecurity FROM pg_class
        WHERE relname IN ('role_assignments','role_assignment_approvals','role_expiry_block_decisions')
        ORDER BY relname
      SQL
      expect(forced.size).to eq(3)
      forced.each do |row|
        expect(row["relrowsecurity"]).to eq("t"), "#{row['relname']} has RLS disabled"
        expect(row["relforcerowsecurity"]).to eq("t"), "#{row['relname']} does not FORCE RLS"
      end
    end

    it "keeps Role Assignment state away from the platform worker entirely" do
      grant(expires_at: t1)
      %w[role_assignments role_assignment_approvals role_expiry_block_decisions].each do |table|
        expect do
          ScheduledActionHarness.as_role("f1_platform_worker") { |pg| pg.exec("SELECT count(*) FROM #{table}") }
        end.to raise_error(PG::InsufficientPrivilege, /permission denied/i)
      end
    end

    it "does not let f1_web claim ScheduledActions" do
      grant(expires_at: t1)
      action = DbInspector.one("SELECT id FROM scheduled_actions")["id"]

      %w[UPDATE DELETE].each do |privilege|
        expect(DbInspector.one("SELECT has_table_privilege('f1_web','scheduled_actions','#{privilege}') AS p")["p"])
          .to eq("f")
      end
      expect(DbInspector.one("SELECT has_function_privilege('f1_web', p.oid, 'EXECUTE') AS p FROM pg_proc p " \
                             "WHERE p.proname = 'f1_claim_due_scheduled_actions' LIMIT 1")&.fetch("p"))
        .to satisfy { |v| v.nil? || v == "f" }
      expect(action).not_to be_nil
    end

    it "does not let f1_web mutate approval history outside the command path" do
      %w[UPDATE DELETE].each do |privilege|
        expect(DbInspector.one("SELECT has_table_privilege('f1_web','role_assignment_approvals','#{privilege}') AS p")["p"])
          .to eq("f")
        expect(DbInspector.one("SELECT has_table_privilege('f1_web','role_expiry_block_decisions','#{privilege}') AS p")["p"])
          .to eq("f")
      end
      # Insert and select are the whole of its authority over both.
      expect(DbInspector.one("SELECT has_table_privilege('f1_web','role_assignment_approvals','INSERT') AS p")["p"])
        .to eq("t")
    end
  end

  # A sole effective OrganizationAdmin whose Assignment is about to expire.
  def sole_admin_with_timer
    target = account("admin2")
    id = TenantSeeder.create_role_assignment(
      organization_id: org, account_id: target, canonical_role: "OrganizationAdmin",
      scope_sha256: org_scope, effective_at: t0, expires_at: t1,
      protected_permission_allowlist: Platform::PermissionBaseline.protected_permission_preview("OrganizationAdmin")
    )
    ScheduledActionHarness.in_context(org) do |_store, correlation_id|
      Workflows::Wf013::RoleAssignmentExpirySchedule.schedule(
        pg: ActiveRecord::Base.connection.raw_connection, organization_id: org,
        role_assignment_id: id, expires_at: t1, now: t0, correlation_id:
      )
    end
    owner.exec_params(
      "UPDATE role_assignments SET status = 'revoked', terminated_at = now() WHERE account_id = $1::uuid",
      [admin[:account_id]]
    )
    id
  end
end
