# frozen_string_literal: true

require "rails_helper"
require "json"
require "yaml"

# REPOSITORY TRUTH — facts that must never again depend on a reviewer noticing them.
#
# S-07-008 went through four independent five-lens review passes. The implementation converged; the
# repository's CLAIMS about it did not. Each pass found false statements in artefacts the previous
# pass had rewritten: a status token invented rather than read from its owning enum, commit fields
# naming a parent commit, a reconciliation note left byte-identical while everything around it moved,
# a table present in the database and absent from the canonical catalogue, and a backlog item
# directing the deletion of a load-bearing index.
#
# Every one was found by a human-equivalent reader comparing two files. That is work a test does
# better, every commit, for nothing. The owner's instruction was to stop asking prose to carry facts
# that belong in executable checks — this file is that instruction.
#
# NOTE ON CITATIONS: these assert DURABLE identifiers — symbols, constraint names, migration names,
# table names, state tokens. Line-number citations are deliberately not validated; they are
# inherently unstable and the acceptance record has been changed to stop making them.
RSpec.describe "Repository truth", type: :model do
  ROOT = Rails.root
  BUILD_STATE = JSON.parse(ROOT.join("specification/automation/BUILD_STATE.json").read)

  def git(*args) = `cd #{ROOT} && git #{args.join(' ')} 2>/dev/null`.strip

  describe "BUILD_STATE is a document the controller can act on" do
    it "carries a status from the owning state machine, not an invented token" do
      $LOAD_PATH.unshift(ROOT.join("automation/lib").to_s)
      require "autonomous_build/state_machine"
      expect(AutonomousBuild::StateMachine::STATES).to include(BUILD_STATE["status"])
    end

    it "names commit fields that exist" do
      %w[implementation_commit review_commit last_verified_commit base_commit].each do |field|
        sha = BUILD_STATE[field]
        next if sha.nil? || sha == "pending" || sha.empty?

        expect(git("cat-file -t #{sha}")).to eq("commit"), "#{field} names #{sha}, which is not a commit"
      end
    end

    it "carries a parseable timestamp that is not in the future" do
      stamp = Time.parse(BUILD_STATE["updated_at"])
      expect(stamp).to be <= Time.now.utc + 60
    end

    it "declares follow-ups with unique ids and no dangling build-item blockers" do
      ids = BUILD_STATE["open_decisions"].map { |d| d["id"] }
      expect(ids.uniq).to eq(ids)

      plan = ROOT.join("specification/automation/BUILD_PLAN.yml").read
      BUILD_STATE["open_decisions"].each do |decision|
        decision["note"].to_s.scan(/S-\d{2}-\d{3}/).uniq.each do |block|
          expect(plan).to include("id: #{block}"),
                          "#{decision['id']} cites #{block}, which is not a BUILD_PLAN block"
        end
      end
    end

    it "does not direct the controller at mechanisms the repository has deleted" do
      # `next_action` is the controller-facing directive. It was once left byte-identical to the
      # tranche's starting commit while everything it described was replaced.
      directive = BUILD_STATE["next_action"].to_s
      deleted = { "claim_limit_event" => "app", "reserve_sitemap_document" => "app" }
      deleted.each do |identifier, dir|
        next unless directive.include?(identifier)

        expect(`cd #{ROOT} && rg -l '#{identifier}' #{dir} 2>/dev/null`).not_to be_empty,
               "next_action directs at `#{identifier}`, which no longer exists in #{dir}/"
      end
    end
  end

  describe "the acceptance record describes something that exists" do
    let(:evidence) { BUILD_STATE["acceptance_evidence"] }
    let(:report) { ROOT.join("S-07-008_COMPLETION_REPORT.md").read }

    it "partitions the tranche diff exactly into accepted paths and excluded contamination" do
      base = evidence["commit_range"].split("..").first
      changed = git("diff --name-only #{base}..HEAD").split("\n")
      accepted = changed.select { |f| evidence["acceptance_diff_paths"].any? { |p| f.start_with?(p) } }
      excluded = changed - accepted

      expect(excluded.sort).to eq(evidence["excluded_contamination"]["files"].sort)
      expect(accepted + excluded).to match_array(changed)
    end

    it "declares the same accepted paths in the state file and the acceptance record" do
      evidence["acceptance_diff_paths"].each do |path|
        expect(report).to include(path), "acceptance record omits declared path #{path}"
      end
    end

    it "cites only file paths that resolve" do
      report.scan(%r{`((?:app|db|spec|lib|schemas|specification)/[\w./-]+)`}).flatten.uniq.each do |path|
        expect(ROOT.join(path)).to exist, "acceptance record cites #{path}, which does not exist"
      end
    end

    it "cites only Ruby identifiers that resolve" do
      report.scan(/`([A-Z]\w+(?:::\w+)*)#(\w+)`/).uniq.each do |const, method|
        klass = const.safe_constantize
        next if klass.nil?   # a class named in prose but not loaded here is out of scope

        expect(klass.instance_methods(false) + klass.private_instance_methods(false))
          .to include(method.to_sym), "acceptance record cites #{const}##{method}, which does not exist"
      end
    end

    it "agrees with the state file about the verified suite size" do
      report_count = report[/RSpec \| \*\*(\d+) examples/, 1]
      state_count = BUILD_STATE["reconciliation_note"][/rspec (\d+)\/0/, 1]
      next if report_count.nil? || state_count.nil?

      expect(report_count).to eq(state_count)
    end
  end

  describe "the canonical schema catalogue is complete" do
    # NOTE the reverse direction is deliberately NOT asserted. `POSTGRESQL_SCHEMA.md` ratifies the
    # whole schema ahead of implementation, so it names ~150 tables S-08 onward will build. A
    # catalogue entry without a table is a plan; a table without a catalogue entry is drift.
    it "represents every application table that exists in the database" do
      catalogue = ROOT.join("schemas/POSTGRESQL_SCHEMA.md").read
      # Rails-internal and F-02 key infrastructure are documented in their own foundation records.
      # The two named gaps are PRE-EXISTING and owned by FU-13; they are listed explicitly so this
      # check protects against NEW omissions without silently absorbing old ones. Removing a name
      # from here must mean the catalogue row was written, never that the check was quietened.
      exempt = %w[ar_internal_metadata schema_migrations
                  f1_context_keys f1_encrypted_records f1_encryption_key_versions
                  evidence role_expiry_block_decisions]
      tables = DbInspector.all(<<~SQL, []).map { |r| r["tablename"] } - exempt
        SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename
      SQL

      missing = tables.reject { |t| catalogue.include?("`#{t}`") }
      expect(missing).to be_empty,
                         "tables in the database but absent from POSTGRESQL_SCHEMA.md: #{missing.join(', ')}"
    end

  end
end
