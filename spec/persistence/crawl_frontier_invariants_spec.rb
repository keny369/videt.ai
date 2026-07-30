# frozen_string_literal: true

require "rails_helper"

# S-07-004 crawl-frontier database invariants (schemas/POSTGRESQL_SCHEMA.md :293-294;
# WORKFLOW_SPECIFICATIONS.md :454; contracts/S-07.json MTX-030 persistence_model). The properties
# that must hold in the database itself: forced tenant RLS, the least-privilege runtime matrix, the
# identity and dequeue uniques, the shape CHECKs, and the exact frontier state edges S-07-004 owns.
#
# Exercised via the BYPASSRLS superuser connection; the same guards are exercised on REAL rows in
# spec/acceptance/wf005_crawl_frontier_spec.rb.
RSpec.describe "Crawl-frontier invariants", type: :model do
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

  let(:org) { TenantSeeder.create_organization(display_name: "Acme Org") }
  def conn = DbInspector.connection

  def draft_project(organization_id: org)
    id = SecureRandom.uuid_v7
    conn.exec_params(<<~SQL, [id, organization_id])
      INSERT INTO projects
        (id, state_version, lock_version, created_at, updated_at, correlation_id, organization_id,
         display_name, locale, time_zone, objective, state, source_set_version)
      VALUES ($1,0,0,now(),now(),gen_random_uuid(),$2,'P','en-AU','UTC','discoverability_assessment','draft',0)
    SQL
    id
  end

  def insert_crawl(pid, organization_id: org)
    id = SecureRandom.uuid_v7
    conn.exec_params(<<~SQL, [id, organization_id, pid])
      INSERT INTO crawls
        (id, state_version, created_at, updated_at, correlation_id, organization_id, project_id, kind,
         requested_entitlement_policy_id, requested_entitlement_policy_version, trigger_kind, queued_at, state)
      VALUES ($1,0,now(),now(),gen_random_uuid(),$2::uuid,$3::uuid,'root',
              gen_random_uuid(),'entitlement-interim-v1','manual',now(),'queued')
    SQL
    id
  end

  def insert_source(pid, host: "s#{SecureRandom.hex(4)}.example", organization_id: org)
    id = SecureRandom.uuid_v7
    conn.exec_params(<<~SQL, [id, organization_id, pid, host])
      INSERT INTO sources
        (id, state_version, created_at, updated_at, correlation_id, organization_id, project_id,
         submitted_root_uri, canonical_root_uri, canonical_host, registration_schema_version,
         host_normalization_version, registration_origin, registering_account_id,
         registration_command_id, registration_idempotency_key_digest,
         registration_authorization_decision_id, registered_at, state)
      VALUES ($1,0,now(),now(),gen_random_uuid(),$2::uuid,$3::uuid,
              'https://'||$4, 'https://'||$4||'/', $4, 'source-registration-v1',
              'ascii-host-v1','human_command',gen_random_uuid(),
              gen_random_uuid(), sha256('k'),
              gen_random_uuid(),now(),'active')
    SQL
    id
  end

  def insert_scope_policy(sid, pid, organization_id: org)
    id = SecureRandom.uuid_v7
    conn.exec_params(<<~SQL, [id, organization_id, pid, sid])
      INSERT INTO source_scope_policies
        (id, created_at, correlation_id, schema_version, organization_id, project_id, source_id,
         policy_version, scope, canonical_host, allowed_schemes, allowed_ports, include_prefixes,
         exclude_prefixes, query_handling, content_sha256)
      VALUES ($1,now(),gen_random_uuid(),'source-scope-policy-v1',$2::uuid,$3::uuid,$4::uuid,
              'source-scope-interim-v1','source','x.example', ARRAY['https'], ARRAY[443], ARRAY['/'],
              ARRAY[]::text[], 'retain_all', sha256('x'))
    SQL
    id
  end

  # A frontier entry with everything the FKs and CHECKs require.
  def insert_entry(ctx, url: "https://x.example/", origin: "root", depth: 0, state: "queued",
                   discovering: "", position: 0, ordinal: 0, order: nil, reason: nil, key: nil, id: nil)
    id ||= SecureRandom.uuid_v7
    key ||= Workflows::Wf005::FrontierOrder.dequeue_key(
      depth:, origin:, canonical_url: url, discovering_document_url: discovering,
      link_position: position, entry_id: id
    )
    params = [id, ctx[:org], ctx[:project], ctx[:crawl], ctx[:source], url,
              { value: url.b, format: 1 }, { value: Digest::SHA256.digest(url), format: 1 },
              ordinal, origin, depth, discovering, position, { value: key, format: 1 },
              ctx[:policy], order || next_order(ctx[:crawl]), state, reason]
    conn.exec_params(<<~SQL, params)
      INSERT INTO crawl_frontier_entries
        (id, state_version, created_at, updated_at, correlation_id, organization_id, project_id,
         crawl_id, source_id, canonical_url, canonical_url_preimage, canonical_url_sha256,
         collision_ordinal, origin, depth, discovering_document_url, link_position, dequeue_key,
         canonicalization_version, scope_policy_id, scope_policy_version, enqueue_order, state, reason)
      VALUES ($1,0,now(),now(),gen_random_uuid(),$2::uuid,$3::uuid,
              $4::uuid,$5::uuid,$6,$7,$8,
              $9,$10,$11,$12,$13,$14,
              'source-scope-interim-v1',$15::uuid,'source-scope-interim-v1',$16,$17,$18)
    SQL
    id
  end

  def next_order(crawl_id)
    conn.exec_params("SELECT COALESCE(MAX(enqueue_order),-1)+1 AS n FROM crawl_frontier_entries WHERE crawl_id=$1::uuid",
                     [crawl_id]).to_a.first["n"].to_i
  end

  def context
    pid = draft_project
    sid = insert_source(pid)
    { org:, project: pid, crawl: insert_crawl(pid), source: sid, policy: insert_scope_policy(sid, pid) }
  end

  # A state change issued as raw SQL, so what is asserted is the DATABASE guard and not a store method
  # declining to offer an edge. Advances `state_version` by exactly one, which the guard also requires.
  def move(id, target)
    conn.exec_params(
      "UPDATE crawl_frontier_entries SET state_version = state_version + 1, state = $2 WHERE id = $1::uuid",
      [id, target])
  end

  def state_of(id) = DbInspector.one("SELECT state FROM crawl_frontier_entries WHERE id=$1::uuid", [id])["state"]

  describe "tenancy and least privilege" do
    { "crawl_frontier_entries" => %w[INSERT SELECT UPDATE], "crawl_frontier_occurrences" => %w[INSERT SELECT] }.each do |table, grants|
      it "forces row level security on #{table} with the tenant-context policy" do
        rel = DbInspector.one("SELECT relrowsecurity AS e, relforcerowsecurity AS f FROM pg_class WHERE relname = $1", [table])
        expect(rel["e"]).to eq("t")
        expect(rel["f"]).to eq("t")
        policy = DbInspector.one("SELECT qual, with_check FROM pg_policies WHERE tablename = $1 AND policyname = $2",
                                 [table, "#{table}_context"])
        expect(policy["qual"]).to include("f1_current_context_org")
        expect(policy["with_check"]).to include("f1_current_context_org")
      end

      it "grants the runtime role exactly #{grants.join('/')} on #{table} (never DELETE)" do
        privs = DbInspector.all(<<~SQL, [table]).map { |r| r["privilege_type"] }.sort
          SELECT privilege_type FROM information_schema.role_table_grants
          WHERE table_name = $1 AND grantee = 'f1_runtime'
        SQL
        expect(privs).to eq(grants)
      end
    end
  end

  describe "candidate identity" do
    it "permits at most one entry per (crawl, digest, collision ordinal)" do
      c = context
      insert_entry(c, url: "https://x.example/a")
      expect { insert_entry(c, url: "https://x.example/a") }
        .to raise_error(PG::UniqueViolation, /crawl_frontier_entries_identity_unique/)
    end

    it "retains BOTH candidates when a digest collides but the ordinal differs (never merges)" do
      c = context
      insert_entry(c, url: "https://x.example/a", ordinal: 0)
      expect { insert_entry(c, url: "https://x.example/a", ordinal: 1) }.not_to raise_error
      expect(DbInspector.all("SELECT * FROM crawl_frontier_entries WHERE crawl_id = $1::uuid", [c[:crawl]]).size).to eq(2)
    end

    it "permits at most one entry per (crawl, dequeue_key), so the order is total" do
      c = context
      id = SecureRandom.uuid_v7
      key = Workflows::Wf005::FrontierOrder.dequeue_key(depth: 0, origin: "root", canonical_url: "https://x.example/",
                                                        discovering_document_url: "", link_position: 0, entry_id: id)
      insert_entry(c, url: "https://x.example/a", key:)
      expect { insert_entry(c, url: "https://x.example/b", key:) }
        .to raise_error(PG::UniqueViolation, /crawl_frontier_entries_dequeue_unique/)
    end
  end

  describe "shape constraints" do
    it "requires a root or sitemap candidate to carry an empty discovering URL and position zero" do
      c = context
      expect { insert_entry(c, origin: "root", discovering: "https://x.example/") }
        .to raise_error(PG::CheckViolation, /crawl_frontier_entries_origin_shape/)
      expect { insert_entry(c, origin: "sitemap", position: 3) }
        .to raise_error(PG::CheckViolation, /crawl_frontier_entries_origin_shape/)
      expect { insert_entry(c, origin: "link", discovering: "https://x.example/", position: 3, depth: 1) }
        .not_to raise_error
    end

    it "requires a root candidate to be depth zero" do
      expect { insert_entry(context, origin: "root", depth: 1) }
        .to raise_error(PG::CheckViolation, /crawl_frontier_entries_root_depth/)
    end

    it "requires exactly the discarded state to carry a reason" do
      c = context
      expect { insert_entry(c, state: "queued", reason: "queue_limit_discarded") }
        .to raise_error(PG::CheckViolation, /crawl_frontier_entries_discard_reason/)
      expect { insert_entry(c, url: "https://x.example/d", state: "discovered", reason: nil) }.not_to raise_error
    end

    it "refuses an unknown origin, a negative depth and a negative link position" do
      c = context
      # An explicit key, so the DATABASE CHECK is what rejects these rather than the pure encoder
      # (which refuses them first in application code — asserted in the FrontierOrder spec).
      key = Workflows::Wf005::FrontierOrder.dequeue_key(depth: 0, origin: "root", canonical_url: "https://x.example/k",
                                                        discovering_document_url: "", link_position: 0,
                                                        entry_id: SecureRandom.uuid_v7)
      expect { insert_entry(c, origin: "guessed", key:) }.to raise_error(PG::CheckViolation, /origin/)
      expect { insert_entry(c, depth: -1, origin: "link", discovering: "https://x.example/", position: 1, key:) }
        .to raise_error(PG::CheckViolation, /depth/)
      expect { insert_entry(c, origin: "link", discovering: "https://x.example/", position: -1, depth: 1, key:) }
        .to raise_error(PG::CheckViolation, /link_position/)
    end
  end

  describe "the exact frontier state edges S-07-004 owns" do
    it "permits admission, the dequeue claim, and the queue-limit discard" do
      c = context
      a = insert_entry(c, url: "https://x.example/a", state: "discovered")
      expect { conn.exec_params("UPDATE crawl_frontier_entries SET state_version = state_version + 1, state='queued' WHERE id=$1::uuid", [a]) }.not_to raise_error
      expect { conn.exec_params("UPDATE crawl_frontier_entries SET state_version = state_version + 1, state='in_progress' WHERE id=$1::uuid", [a]) }.not_to raise_error
      b = insert_entry(c, url: "https://x.example/b", state: "discovered")
      expect { conn.exec_params("UPDATE crawl_frontier_entries SET state_version = state_version + 1, state='discarded', reason='queue_limit_discarded' WHERE id=$1::uuid", [b]) }
        .not_to raise_error
    end

    # THE SEAL RELEASE, delivered by S-07-012 under the owner's ruling in DECISIONS ADR-087. This
    # replaces an assertion that refused all three edges out of `in_progress` and recorded them as
    # "later tranches'". It is deliberately STRONGER than what it replaces: it fixes the ONE edge that
    # exists, the ONE source state it may leave, and the exhaustive set of states from which it is
    # refused — and it still refuses `fetched_pending_commit`, whose coordinator limb (:456's "a
    # completion with a later key waits in `fetched_pending_commit`; it cannot change selection") arrives
    # with concurrent fetching and link extraction and remains S-07-010's.
    it "permits ONLY in_progress -> terminal out of a claimed entry" do
      c = context
      a = insert_entry(c, url: "https://x.example/a", state: "in_progress")
      %w[fetched_pending_commit queued discovered discarded].each do |target|
        expect { move(a, target) }
          .to raise_error(PG::RaiseException, /crawl_frontier_transition_unavailable in_progress -> #{target}/),
              "in_progress -> #{target} was permitted"
      end
      expect { move(a, "terminal") }.not_to raise_error
      expect(state_of(a)).to eq("terminal")
    end

    it "refuses terminal from every state except in_progress, and refuses every edge OUT of terminal" do
      c = context
      # `discarded` needs its reason (`crawl_frontier_entries_discard_reason`), and
      # `fetched_pending_commit` is INSERTED directly because no legal edge reaches it — which is the
      # point: even a row that arrived there some other way cannot be retired by this transition.
      { "queued" => nil, "discovered" => nil, "fetched_pending_commit" => nil, "discarded" => "queue_limit_discarded" }
        .each_with_index do |(source, reason), i|
          row = insert_entry(c, url: "https://x.example/from-#{i}", state: source, reason:)
          expect { move(row, "terminal") }
            .to raise_error(PG::RaiseException, /crawl_frontier_transition_unavailable #{source} -> terminal/),
                "#{source} -> terminal was permitted"
        end

      # A coverage-bearing terminal decision is never rewritten: no edge leaves `terminal`.
      done = insert_entry(c, url: "https://x.example/done", state: "in_progress")
      move(done, "terminal")
      %w[queued in_progress fetched_pending_commit discovered discarded].each do |target|
        expect { move(done, target) }
          .to raise_error(PG::RaiseException, /crawl_frontier_transition_unavailable terminal -> #{target}/),
              "terminal -> #{target} was permitted"
      end
      # And `terminal` carries no discard reason, which the shape CHECK requires of every state but one.
      expect(DbInspector.one("SELECT reason FROM crawl_frontier_entries WHERE id=$1::uuid", [done])["reason"]).to be_nil
    end

    it "freezes candidate IDENTITY and provenance in every state, and refuses DELETE" do
      c = context
      a = insert_entry(c, url: "https://x.example/a")
      {
        "canonical_url" => "'https://x.example/z'", "collision_ordinal" => "7",
        "enqueue_order" => "42", "scope_policy_version" => "'other'",
        "canonicalization_version" => "'other'", "source_id" => "gen_random_uuid()"
      }.each do |column, value|
        expect { conn.exec_params("UPDATE crawl_frontier_entries SET state_version = state_version + 1, #{column} = #{value} WHERE id = $1::uuid", [a]) }
          .to raise_error(PG::RaiseException, /crawl_frontier_entry_facts_immutable/), "#{column} was mutable"
      end
      expect { conn.exec_params("DELETE FROM crawl_frontier_entries WHERE id = $1::uuid", [a]) }
        .to raise_error(PG::RaiseException, /crawl_frontier_entry_immutable/)
    end

    # S-07-004 review hardening: :454 requires deduplication to retain the LOWEST-ordered discovery
    # and the queue bound to retain the LOWEST 20,000, both of which need a candidate's POSITION to
    # improve after it is committed. The window closes at the claim.
    it "lets an UNCLAIMED entry's position change, and freezes it from the claim onward" do
      c = context
      a = insert_entry(c, url: "https://x.example/a", origin: "link", depth: 1,
                       discovering: "https://x.example/z", position: 2)
      %w[discovered queued].each do |state|
        conn.exec_params("UPDATE crawl_frontier_entries SET state_version = state_version + 1, state = $2 WHERE id = $1::uuid AND state <> $2", [a, state]) if state == "queued"
        expect { conn.exec_params("UPDATE crawl_frontier_entries SET state_version = state_version + 1, discovering_document_url = 'https://x.example/a' WHERE id = $1::uuid", [a]) }
          .not_to raise_error
      end
      expect { conn.exec_params("UPDATE crawl_frontier_entries SET state_version = state_version + 1, dequeue_key = '\\x0102'::bytea WHERE id = $1::uuid", [a]) }
        .not_to raise_error

      conn.exec_params("UPDATE crawl_frontier_entries SET state_version = state_version + 1, state = 'in_progress' WHERE id = $1::uuid", [a])
      { "depth" => "5", "link_position" => "9", "origin" => "'sitemap'",
        "discovering_document_url" => "'https://x.example/q'", "dequeue_key" => "'\\x00'::bytea" }.each do |column, value|
        expect { conn.exec_params("UPDATE crawl_frontier_entries SET state_version = state_version + 1, #{column} = #{value} WHERE id = $1::uuid", [a]) }
          .to raise_error(PG::RaiseException, /crawl_frontier_entry_position_frozen/), "#{column} was mutable after the claim"
      end
    end

    it "permits evicting an ADMITTED but unclaimed candidate at the queue bound" do
      c = context
      a = insert_entry(c, url: "https://x.example/a", state: "queued")
      expect { conn.exec_params("UPDATE crawl_frontier_entries SET state_version = state_version + 1, state='discarded', reason='queue_limit_discarded' WHERE id=$1::uuid", [a]) }
        .not_to raise_error
    end
  end

  describe "occurrences are T-IMM" do
    def insert_occurrence(c, entry_id, position: 1, order: 0)
      id = SecureRandom.uuid_v7
      conn.exec_params(<<~SQL, [id, c[:org], c[:project], c[:crawl], entry_id, c[:source], position, order])
        INSERT INTO crawl_frontier_occurrences
          (id, created_at, correlation_id, organization_id, project_id, crawl_id, frontier_entry_id,
           source_id, occurrence_url, occurrence_url_sha256, discovering_document_url, link_position,
           occurrence_order, discovered_at, duplicate_reason)
        VALUES ($1,now(),gen_random_uuid(),$2::uuid,$3::uuid,$4::uuid,$5::uuid,
                $6::uuid,'https://x.example/a', sha256('a'), 'https://x.example/', $7,
                $8, now(), 'duplicate_discovery')
      SQL
      id
    end

    it "refuses every UPDATE and DELETE" do
      c = context
      oid = insert_occurrence(c, insert_entry(c))
      expect { conn.exec_params("UPDATE crawl_frontier_occurrences SET link_position = 9 WHERE id = $1::uuid", [oid]) }
        .to raise_error(PG::RaiseException, /crawl_frontier_occurrence_immutable/)
      expect { conn.exec_params("DELETE FROM crawl_frontier_occurrences WHERE id = $1::uuid", [oid]) }
        .to raise_error(PG::RaiseException, /crawl_frontier_occurrence_immutable/)
    end

    it "permits at most one occurrence per (entry, discovering URL, position) and per order" do
      c = context
      entry = insert_entry(c)
      insert_occurrence(c, entry, position: 1, order: 0)
      expect { insert_occurrence(c, entry, position: 1, order: 1) }
        .to raise_error(PG::UniqueViolation, /crawl_frontier_occurrences_identity_unique/)
      expect { insert_occurrence(c, entry, position: 2, order: 0) }
        .to raise_error(PG::UniqueViolation, /crawl_frontier_occurrences_order_unique/)
    end
  end

  describe "composite tenant foreign keys" do
    it "rejects an entry naming a Crawl or Source from another Project of the same Organization" do
      c = context
      other = context
      expect { insert_entry(c.merge(crawl: other[:crawl])) }
        .to raise_error(PG::ForeignKeyViolation, /crawl_frontier_entries_crawl_fk/)
      expect { insert_entry(c.merge(source: other[:source])) }
        .to raise_error(PG::ForeignKeyViolation, /crawl_frontier_entries_source_fk/)
    end
  end
end
