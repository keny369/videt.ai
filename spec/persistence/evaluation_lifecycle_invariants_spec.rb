# frozen_string_literal: true

require "rails_helper"

# `f1_evaluations_guard` — the Evaluation lifecycle edges, proved AT THE WRITE.
#
# The guard is what stops a defect anywhere in the application writing an Evaluation state
# no workflow is entitled to produce. It was fully closed ("refuse every state change ...
# S-08/S-09 relax the lifecycle edges") and is now open by exactly two edges. The value of
# this file is the REFUSALS: `running -> completed` belongs to WF-007's Issue-set seal and
# `-> superseded` to WF-011, neither of which exists, so both must still raise. If a later
# slice opens them it will fail here first and have to say so deliberately.
RSpec.describe "Evaluation lifecycle invariants", type: :persistence do
  self.use_transactional_tests = false

  after { ReceiptMinter.truncate_all }

  let(:org) { TenantSeeder.create_organization(display_name: "Acme Org") }
  def conn = DbInspector.connection

  def draft_project
    id = SecureRandom.uuid_v7
    conn.exec_params(<<~SQL, [id, org])
      INSERT INTO projects
        (id, state_version, lock_version, created_at, updated_at, correlation_id, organization_id,
         display_name, locale, time_zone, objective, state, source_set_version)
      VALUES ($1,0,0,now(),now(),gen_random_uuid(),$2,'P','en-AU','UTC','discoverability_assessment','draft',0)
    SQL
    id
  end

  def insert_crawl(project_id)
    id = SecureRandom.uuid_v7
    conn.exec_params(<<~SQL, [id, org, project_id])
      INSERT INTO crawls
        (id, state_version, created_at, updated_at, correlation_id, organization_id, project_id, kind,
         requested_entitlement_policy_id, requested_entitlement_policy_version, trigger_kind, queued_at, state)
      VALUES ($1,0,now(),now(),gen_random_uuid(),$2::uuid,$3::uuid,'root',
              gen_random_uuid(),'entitlement-interim-v1','manual',now(),'queued')
    SQL
    id
  end

  # A pending initial Evaluation with the minimum the guard's immutability rules need.
  # Written on the BYPASSRLS inspector connection: this proves the database's own refusal,
  # which must hold for any writer, not only for one that went through a handler.
  def seeded_evaluation
    project = draft_project
    crawl = insert_crawl(project)
    id = SecureRandom.uuid
    conn.exec_params(<<~SQL, [id, org, project, crawl])
      INSERT INTO evaluations (id, created_at, updated_at, correlation_id, organization_id,
                               project_id, crawl_id, kind, state)
      VALUES ($1::uuid, now(), now(), gen_random_uuid(), $2::uuid, $3::uuid, $4::uuid, 'initial', 'pending')
    SQL
    id
  end

  def transition(id, to_state, **columns)
    sets = ["state = #{conn.escape_literal(to_state)}", "state_version = state_version + 1"]
    columns.each { |name, value| sets << "#{name} = #{value.nil? ? "NULL" : "now()"}" }
    conn.exec("UPDATE evaluations SET #{sets.join(", ")} WHERE id = #{conn.escape_literal(id)}::uuid")
  end

  def state_of(id) = conn.exec_params("SELECT state FROM evaluations WHERE id = $1::uuid", [id]).to_a.first["state"]

  describe "the two edges the WF-006 input gate performs" do
    it "admits pending -> running when the instant is stamped with it" do
      id = seeded_evaluation

      transition(id, "running", started_at: :now)

      expect(state_of(id)).to eq("running")
    end

    it "admits running -> failed when the instant is stamped with it" do
      id = seeded_evaluation
      transition(id, "running", started_at: :now)

      transition(id, "failed", failed_at: :now)

      expect(state_of(id)).to eq("failed")
    end

    it "refuses a transition that does not stamp its instant" do
      id = seeded_evaluation

      expect { transition(id, "running", started_at: nil) }
        .to raise_error(PG::RaiseException, /evaluation_transition_instant_required running/)
      expect(state_of(id)).to eq("pending")
    end
  end

  describe "the edges no workflow in this build may perform" do
    it "refuses the pending -> failed shortcut, so `running` is always recorded" do
      id = seeded_evaluation

      expect { transition(id, "failed", failed_at: :now) }
        .to raise_error(PG::RaiseException, /evaluation_transition_unavailable pending -> failed/)
      expect(state_of(id)).to eq("pending")
    end

    it "refuses running -> completed, which is WF-007's unbuilt Issue-set seal" do
      id = seeded_evaluation
      transition(id, "running", started_at: :now)

      expect { transition(id, "completed", completed_at: :now) }
        .to raise_error(PG::RaiseException, /evaluation_transition_unavailable running -> completed/)
    end

    it "refuses -> superseded, which is WF-011's unbuilt reassessment path" do
      id = seeded_evaluation

      expect { transition(id, "superseded", superseded_at: :now) }
        .to raise_error(PG::RaiseException, /evaluation_transition_unavailable pending -> superseded/)
    end

    it "refuses reopening a terminal Evaluation" do
      id = seeded_evaluation
      transition(id, "running", started_at: :now)
      transition(id, "failed", failed_at: :now)

      expect { transition(id, "running", started_at: :now) }
        .to raise_error(PG::RaiseException, /evaluation_transition_unavailable failed -> running/)
    end
  end

  describe "what the guard always refused, and still does" do
    it "refuses DELETE" do
      id = seeded_evaluation

      expect { conn.exec_params("DELETE FROM evaluations WHERE id = $1::uuid", [id]) }
        .to raise_error(PG::RaiseException, /evaluation_immutable/)
    end

    it "refuses re-pointing an Evaluation at another Crawl" do
      id = seeded_evaluation

      expect do
        conn.exec_params("UPDATE evaluations SET crawl_id = gen_random_uuid() WHERE id = $1::uuid", [id])
      end.to raise_error(PG::RaiseException, /evaluation_facts_immutable/)
    end
  end
end
