# frozen_string_literal: true

require "json"

module IdentityAccess
  module Infrastructure
    # Persistence for WF-005 ActivateCrawlPolicy (S-07-001), written in the actor's unit of
    # work inside the proved Organization context. The dedicated `crawl_policies` table (owner
    # D1, DECISIONS ADR-068) mirrors the source_scope_policies shape: immutable content, a
    # single active -> superseded lifecycle edge. It reuses ActorLedgerWriters and overrides
    # only the two writers that stamp `workflow_id` = 'WF-005'.
    class CrawlPolicyStore
      include ActorLedgerWriters

      def initialize(pg_connection)
        @pg = pg_connection
      end

      # Serialize ALL crawl-policy activations for one Organization (organization AND project
      # scope) so a project activation cannot race an Organization-scope supersession of its
      # parent, and exactly one new version per scope wins; the loser's expected-version guard
      # then fails cleanly. Crawl-policy activation is a rare administrative operation, so a
      # single per-Organization lock is ample and avoids the cross-scope race (ADR-026 NB-1).
      def lock_organization(organization_id)
        exec("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", ["crawl-policy:#{organization_id}"])
      end

      # The current active crawl policy version for the scope, or nil (project_id NULL for
      # organization scope; IS NOT DISTINCT FROM matches NULL to NULL).
      def active_policy(organization_id, scope, project_id)
        exec(<<~SQL, [organization_id, scope, project_id]).to_a.first
          SELECT id, state_version, policy_version, scope, normalized_bounds,
                 encode(content_sha256,'hex') AS content_hex
          FROM crawl_policies
          WHERE organization_id = $1::uuid AND scope = $2
            AND project_id IS NOT DISTINCT FROM $3::uuid AND state = 'active'
        SQL
      end

      # The number of existing versions for the scope — the ordinal a new version takes
      # (crawl-policy-{scope}-v{N}); read under the per-scope lock.
      def version_count(organization_id, scope, project_id)
        exec(<<~SQL, [organization_id, scope, project_id]).to_a.first["n"].to_i
          SELECT COUNT(*) AS n FROM crawl_policies
          WHERE organization_id = $1::uuid AND scope = $2 AND project_id IS NOT DISTINCT FROM $3::uuid
        SQL
      end

      # POLICY ACTIVATION IS ONE STATEMENT, AND IT CARRIES ITS OWN AUTHORITY CHECK.
      #
      # WHY ONE STATEMENT. The transition is two writes — supersede the prior active version, insert
      # the new one — and the scope's one-active-per-scope partial-unique index means a half-applied
      # transition is a corrupt scope: superseded with nothing active, or two active rows. Run as two
      # statements with authority tested in each, a revocation landing BETWEEN them denies the second
      # while the first stands. Run as two statements with authority tested in Ruby, the test can be
      # hoisted, reordered or deleted. Neither is acceptable, so the supersede and the insert are one
      # statement whose data-modifying CTEs share a single evaluation of one authority predicate.
      # PostgreSQL applies both or neither, and `inserted` depends on `superseded`, which forces the
      # order rather than leaving it to the planner.
      #
      # WHY THE PREDICATE IS ORDINARY ROW STATE. `authority_current?` is, in full,
      # "`organizations.authorization_epoch` equals the epoch the actor authenticated with", so it
      # belongs in the statement that depends on it. There is then no handler-level check to hoist and
      # no list of which handlers must remember to perform one.
      #
      # THE LOCK STRENGTH IS `FOR SHARE`, NOT `FOR KEY SHARE` (D7). An epoch advance changes no key,
      # so it takes `FOR NO KEY UPDATE`, which does not conflict with `FOR KEY SHARE` — measured on
      # this branch, a revocation committed straight through a `FOR KEY SHARE` reader. `FOR SHARE`
      # conflicts with it and not with a second authorized reader.
      #
      # THE CAPABILITY AXIS IS A CONJUNCT TOO (FU-48): the granting Role Assignments the decision
      # relied on are re-read in this statement, active, effective, unexpired, at the version and
      # scope the decision saw.
      #
      # THE OUTCOMES ARE REPORTED SEPARATELY because the contract distinguishes them: authority that
      # moved or a capability that is gone are DOMAIN DENIALS, a prior version that would not
      # supersede is a LOST SERIALIZED TRANSITION the handler raises on, and a successful pair is the
      # transition.
      def activate_version(row)
        authority = row.fetch(:authority)
        # THE AUTHORITY'S ORGANIZATION IS THE ONLY ONE THIS STATEMENT MAY REASON ABOUT (FU-50). The
        # row's organization still selects the SCOPE being superseded and is the value inserted; both
        # authority limbs bind `$21`, which comes from the authenticated Session. See
        # `WriteAuthority#governs!` for why the equality is refused here rather than left to RLS.
        authority.governs!(row[:organization_id], at: "CrawlPolicyStore#activate_version")
        params = [
          row[:id], iso(row[:now]), row[:correlation_id], row[:organization_id], row[:project_id],
          row[:scope], row[:policy_version], row[:supersedes_id], row[:activated_by_account_id],
          JSON.generate(row[:normalized_bounds]), bytea(row[:content_sha256]),
          row[:expected_state_version], authority.epoch, authority.uuid_array,
          authority.bigint_array, authority.text_array, authority.account_id,
          authority.required_role, authority.allowed_roles_array, authority.read_only_permitted,
          authority.organization_id, authority.protected_capability, authority.capability,
          authority.required_scope_hex
        ]
        result = exec(<<~SQL, params).to_a.first
          WITH epoch_authority AS (
            SELECT 1 FROM organizations
            WHERE id = $21::uuid AND authorization_epoch = $13::bigint
            FOR SHARE
          ), capability_authority AS (
            SELECT 1 FROM role_assignments ra
            JOIN unnest($14::uuid[], $15::bigint[], $16::text[]) AS g(id, state_version, scope_hex)
              ON g.id = ra.id AND g.state_version = ra.state_version
             AND g.scope_hex = coalesce(encode(ra.scope_sha256, 'hex'), '')
            WHERE ra.organization_id = $21::uuid AND ra.account_id = $17::uuid
              AND ra.status = 'active'
              AND ra.effective_at IS NOT NULL AND ra.effective_at <= $2::timestamptz
              AND (ra.expires_at IS NULL OR $2::timestamptz < ra.expires_at)
              -- THE SCOPE RULE, AS A PREDICATE RATHER THAN AS A RUBY OPERAND (FU-48). `:732`/`:738`
              -- THE CAPABILITY ITSELF, AS A PREDICATE (round-17 finding R17-SEC-1). The rest of
              -- this CTE asks whether the carried grant is still LIVE; without this line it never
              -- asked what the grant CONFERS, so a role the ratified baseline denies satisfied it.
              -- The cell is immutable for the life of a deploy and is read once in Ruby, so this is
              -- the baseline CARRIED, not a second copy of the six-step algorithm.
              AND ra.canonical_role = ANY ($19::text[])
              -- THE SIXTH COLUMN, WHICH `CAPABILITIES` CANNOT EXPRESS (round-18 finding CB-1). A
              -- Read-Only Executive Buyer carries a `canonical_role` that IS in the cell above, and
              -- the ratified table denies it this capability; measured, it cancelled a running Crawl.
              AND ($20::boolean OR ra.permission_mode <> 'read_only')
              -- bind Organization scope to OrganizationAdmin and Project scope to MarketingOperator.
              -- Removing the Ruby operand that said so let a MarketingOperator commit an
              -- ORGANIZATION-scope policy through 2364 green examples; the statement now refuses it.
              AND ($18::text IS NULL OR ra.canonical_role = $18::text)
              -- THE PROTECTED LIMB, WHICH THIS STATEMENT DID NOT CARRY (FU-58). `confers?` is FOUR
              -- limbs and the CTE bound two: a capability in `PROTECTED` additionally requires the
              -- Assignment's bootstrap-admin exception or its APPROVED allowlist. Measured, an
              -- ordinary OrganizationAdmin grant with capability `role.manage` was denied by Ruby
              -- and authorized here. `PROTECTED` is immutable for the life of a deploy and read once
              -- in `WriteAuthority.for`; what is re-read here is only row state another transaction
              -- can move.
              AND (NOT $22::boolean
                   OR ra.bootstrap_admin_exception
                   OR ra.protected_permission_allowlist @> to_jsonb($23::text))
              -- ASSIGNMENT-SCOPE CONTAINMENT AGAINST THE TARGET (FU-2, sited by FU-49). `$18` above
              -- carries the ratified rule that an ORGANIZATION-scope policy demands an
              -- OrganizationAdmin; it says nothing about the scope that Admin's own Assignment
              -- holds. Measured: an OrganizationAdmin whose Assignment carries a PROJECT scope
              -- digest activated an immutable Organization-wide policy, authorized by both limbs.
              -- `$24` is the scope an Assignment must hold to contain this write's target — exactly
              -- Organization scope for an Organization-scope policy, and NULL at Project scope,
              -- where `role_assignments` holds only a one-way digest of the grant's `GrantScope`
              -- and no single scope answers containment. See `WriteAuthority` for why the resource
              -- limb of FU-2 stays open rather than being approximated here.
              AND ($24::text IS NULL
                   OR ra.scope_sha256 IS NULL
                   OR encode(ra.scope_sha256, 'hex') = $24::text)
            FOR SHARE OF ra
          ), authority AS (
            SELECT 1 WHERE EXISTS (SELECT 1 FROM epoch_authority)
                       AND EXISTS (SELECT 1 FROM capability_authority)
          ), superseded AS (
            UPDATE crawl_policies
            SET state = 'superseded', superseded_at = $2::timestamptz,
                state_version = state_version + 1, updated_at = $2::timestamptz
            WHERE $8::uuid IS NOT NULL AND id = $8::uuid AND state = 'active'
              AND state_version = $12::int
              -- THE SUPERSEDED ROW MUST BELONG TO THE SCOPE BEING ACTIVATED.
              --
              -- Without these three predicates the CTE matched on `id` alone, so a `supersedes_id`
              -- naming another scope's active version superseded THAT scope and activated this one,
              -- reporting {authorized: true, superseded: 1, inserted: 1} — a fully successful
              -- transition by every signal the caller has, leaving the other scope with ZERO active
              -- versions. `f1_crawl_policies_guard` makes a superseded row terminal, so the emptied
              -- scope cannot be restored, only re-activated. RLS barred the cross-TENANT case; nothing
              -- barred the cross-SCOPE one, and the store must hold its own contract rather than
              -- depend on the one caller that happens to derive the id correctly.
              AND organization_id = $4::uuid
              AND scope = $6
              AND project_id IS NOT DISTINCT FROM $5::uuid
              AND EXISTS (SELECT 1 FROM authority)
            RETURNING 1
          ), inserted AS (
            INSERT INTO crawl_policies
              (id, state_version, created_at, updated_at, correlation_id, schema_version, organization_id,
               project_id, scope, policy_version, state, supersedes_id, activated_by_account_id,
               normalized_bounds, content_sha256, superseded_at)
            SELECT $1,0,$2::timestamptz,$2::timestamptz,$3::uuid,'crawl-policy-v1',$4::uuid,
                   $5::uuid,$6,$7,'active',$8::uuid,$9::uuid,$10::jsonb,$11,NULL
            WHERE EXISTS (SELECT 1 FROM authority)
              AND ($8::uuid IS NULL OR EXISTS (SELECT 1 FROM superseded))
            RETURNING 1
          )
          SELECT (SELECT count(*) FROM epoch_authority) AS epoch_authorized,
                 (SELECT count(*) FROM capability_authority) AS capability_authorized,
                 (SELECT count(*) FROM superseded) AS superseded,
                 (SELECT count(*) FROM inserted) AS inserted
        SQL
        epoch = result["epoch_authorized"].to_i.positive?
        capability = result["capability_authorized"].to_i.positive?
        { authorized: epoch && capability, epoch_authorized: epoch, capability_authorized: capability,
          superseded: result["superseded"].to_i, inserted: result["inserted"].to_i }
      end

      # WF-005 audit writer — ActorLedgerWriters row shape stamped 'WF-005'.
      def insert_audit(row)
        params = [
          row[:id], row[:occurred_at], row[:partition_month], row[:organization_id], row[:actor_id],
          row[:correlation_id], row[:causation_id], row[:command_id], row[:entity_type], row[:entity_id],
          row[:to_state], row[:outcome], row[:reason_code], row[:payload], bytea(row[:content_sha256])
        ]
        exec(<<~SQL, params)
          INSERT INTO audit_record_registry
            (id, schema_version, created_at, occurred_at, partition_month, organization_id, workflow_id,
             actor_id, correlation_id, causation_id, command_id, entity_type, entity_id,
             to_state, outcome, reason_code, classification, payload, content_sha256, retention_class)
          VALUES ($1,'1.0',$2::timestamptz,$2::timestamptz,$3::date,$4::uuid,'WF-005',
                  $5::uuid,$6::uuid,$7::uuid,$8::uuid,$9,$10::uuid,$11,$12,$13,'restricted',$14::jsonb,$15,'security_audit')
        SQL
      end

      # WF-005 event writer — ActorLedgerWriters row shape stamped 'WF-005'.
      def insert_event(row)
        params = [
          row[:id], row[:created_at], row[:event_type], row[:event_profile], row[:occurred_at],
          row[:organization_id], row[:aggregate_type], row[:aggregate_id], row[:aggregate_version],
          row[:partition_month], row[:correlation_id], row[:causation_id], row[:command_id],
          row[:audit_record_id], bytea(row[:event_bytes]), row[:event_bytes].bytesize, bytea(row[:event_sha256])
        ]
        exec(<<~SQL, params)
          INSERT INTO event_registry
            (id, schema_version, created_at, event_type, event_schema_version, workflow_id, event_profile,
             occurred_at, organization_id, aggregate_type, aggregate_id, aggregate_version, partition_month,
             correlation_id, causation_id, command_id, audit_record_id, event_bytes, event_byte_count, event_sha256)
          VALUES ($1,'1.0',$2::timestamptz,$3,'1.0','WF-005',$4,
                  $5::timestamptz,$6::uuid,$7,$8::uuid,$9,$10::date,
                  $11::uuid,$12::uuid,$13::uuid,$14::uuid,$15,$16,$17)
        SQL
      end

      private

      def exec(sql, params) = @pg.exec_params(sql, params)
      def bytea(bytes) = bytes && { value: bytes, format: 1 }
      def iso(time) = time&.getutc&.iso8601(6)
    end
  end
end
