# frozen_string_literal: true

require "rails_helper"
require "json"
require "yaml"
require "open3"

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

  SHA = /\A[0-9a-f]{7,40}\z/

  # NO SHELL. Values here come from a controller-written JSON file that this very spec exists to
  # distrust, and the previous form interpolated them into backticks — a `commit_range` of
  # `$(...)` executed and then emitted a valid SHA, so the payload ran and the assertion passed.
  # argv form, explicit status, no `2>/dev/null` swallowing failure.
  def git(*args)
    out, status = Open3.capture2("git", "-C", ROOT.to_s, *args, err: File::NULL)
    [out.strip, status.success?]
  end

  def git!(*args) = git(*args).first

  # Every SHA-shaped value is validated before it reaches git at all.
  def sha!(value, field)
    expect(value).to match(SHA), "#{field} is #{value.inspect}, which is not a SHA"
    value
  end

  describe "BUILD_STATE is a document the controller can act on" do
    it "carries a status from the owning state machine, not an invented token" do
      $LOAD_PATH.unshift(ROOT.join("automation/lib").to_s)
      require "autonomous_build/state_machine"
      expect(AutonomousBuild::StateMachine::STATES).to include(BUILD_STATE["status"])
    end

    it "names commit fields that are REACHABLE FROM HEAD, not merely objects that exist" do
      # `cat-file -t` is not enough: an amended or rebased commit survives as a dangling object and
      # answers "commit" while naming a tree nobody will ever review. Reachability is the property
      # that matters.
      %w[implementation_commit review_commit last_verified_commit base_commit].each do |field|
        sha = BUILD_STATE[field]
        next if sha.nil? || sha == "pending" || sha.empty?

        sha!(sha, field)
        expect(git!("cat-file", "-t", sha)).to eq("commit"), "#{field} names #{sha}, which is not a commit"
        expect(git("merge-base", "--is-ancestor", sha, "HEAD").last).to be(true),
               "#{field} names #{sha}, which is not reachable from HEAD"
      end
    end

    it "names an implementation commit that contains the tranche" do
      sha = BUILD_STATE["implementation_commit"]
      next if sha.nil? || sha == "pending"

      paths = BUILD_STATE["acceptance_evidence"]["acceptance_diff_paths"]
      base = sha!(BUILD_STATE["acceptance_evidence"]["commit_range"].split("..").first, "range base")
      sha!(sha, "implementation_commit")

      # Descendancy first. `diff base..sha` is symmetric in the paths it names, so a commit that
      # PRECEDES the range answers identically to one that contains it — the direction has to be
      # asserted separately or the check reads an inverse diff as containment.
      expect(git("merge-base", "--is-ancestor", base, sha).last).to be(true),
             "implementation_commit #{sha} predates the declared range base #{base}"

      # The commit's OWN diff, not the cumulative range — `base..sha` would pass on the strength of
      # its predecessors, so a commit touching only excluded paths read as containment.
      changed = git!("show", "--name-only", "--format=", sha).split("\n").reject(&:empty?)
      expect(changed.any? { |f| paths.any? { |p| f.start_with?(p) } }).to be(true),
             "implementation_commit #{sha} contains none of the declared acceptance paths"
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

    it "keeps next_action current with the open decisions it summarises" do
      # `next_action` is the controller-facing directive and has twice been left byte-identical
      # while everything it described was replaced. A hardcoded denylist of two deleted identifiers
      # could not detect that — and would have been satisfied by the very comment recording a
      # deletion. This instead ties it to the record it summarises: any follow-up it names must
      # exist, and any it declares blocking must actually be blocking.
      directive = BUILD_STATE["next_action"].to_s
      ids = BUILD_STATE["open_decisions"].to_h { |d| [d["id"], d] }

      directive.scan(/\bFU-\d+\b/).uniq.each do |fu|
        expect(ids).to have_key(fu), "next_action names #{fu}, which is not an open decision"
      end

      # Anything next_action calls blocking must say so in its own record, and vice versa.
      blocking_in_record = ids.values.select { |d| d["note"].to_s.include?("BLOCKING") }.map { |d| d["id"] }
      blocking_in_record.each do |fu|
        expect(directive).to include(fu),
                             "#{fu} is recorded BLOCKING but next_action does not mention it"
      end
    end

    it "keeps updated_at at or after the commit it names" do
      # "Not in the future" cannot detect staleness, and the field was left three commits behind
      # while the record around it was rewritten. The relationship the repository actually intends
      # is that the stamp is no older than the work it describes.
      sha = BUILD_STATE["implementation_commit"]
      next if sha.nil? || sha == "pending"

      committed = Time.parse(git!("log", "-1", "--format=%cI", sha!(sha, "implementation_commit")))
      expect(Time.parse(BUILD_STATE["updated_at"])).to be >= committed,
                                                       "updated_at predates implementation_commit"
    end
  end

  describe "the acceptance record describes something that exists" do
    let(:evidence) { BUILD_STATE["acceptance_evidence"] }

    # THE REPORT IS DERIVED FROM THE ACCEPTED BLOCK, NOT HARDCODED. This read `S-07-008_COMPLETION_REPORT.md`
    # by name, so every check below went on validating a SUPERSEDED tranche's record while the record
    # actually being accepted was checked by nothing — which is precisely the gap `S-07-012_COMPLETION_REPORT.md`
    # declared in its own opening paragraph ("this document's path partition and citations are asserted for
    # S-07-008 and not for this tranche"). Pointing it at `acceptance_evidence.block` was named there as part
    # of the acceptance transition, and this is that change.
    let(:report_path) { ROOT.join("#{evidence.fetch('block')}_COMPLETION_REPORT.md") }
    let(:report) do
      expect(report_path).to exist, "acceptance_evidence names block #{evidence['block']}, which has no report"
      report_path.read
    end

    # THE RANGE IS BOUNDED AT BOTH ENDS, and both ends are read from the record.
    #
    # This check used to parse the base out of `commit_range` and then DISCARD the endpoint,
    # diffing `base..HEAD` instead. That silently converted a statement about one tranche into a
    # statement about every future commit on the branch: any later authorized work touching a path
    # outside S-07-008's accepted paths broke an accepted record it had nothing to do with. A
    # dependency-security commit upgrading Rails to 8.1.3.1 is what demonstrated it — `Gemfile` and
    # `Gemfile.lock` appeared in a partition they postdate by four commits.
    #
    # The repository's authority is bounded. ADR-083: the tranche "is reviewed BY PATH over a
    # COMMIT RANGE". `acceptance_evidence.verified`: the declared paths and the excluded set
    # "account for every file changed IN THE RANGE". `excluded_contamination.reason` scopes that
    # list to the `git add -A` sweep in two named commits. None of the three claims anything about
    # later work, and the honest repair to a later change is its own commit, not an entry in an
    # accepted record describing something that had not yet happened.
    it "partitions the tranche diff exactly into accepted paths and excluded contamination" do
      base, head = evidence["commit_range"].split("..")
      sha!(base, "commit_range base")
      sha!(head, "commit_range endpoint")

      changed = git!("diff", "--name-only", "#{base}..#{head}").split("\n")
      accepted = changed.select { |f| evidence["acceptance_diff_paths"].any? { |p| f.start_with?(p) } }

      # `excluded` was previously derived as `changed - accepted` and then asserted to recompose
      # into `changed`, which is true by construction. The real assertion is that the RECORDED
      # exclusion list equals what the declared paths leave behind.
      expect((changed - accepted).sort).to eq(evidence["excluded_contamination"]["files"].sort)
      expect(changed).not_to be_empty
    end

    it "names a commit range whose endpoint is real, reachable and after its base" do
      # The endpoint was previously discarded, so it was never validated at all: it could have
      # named a fabricated SHA, an orphaned object, or a commit PRECEDING the base, and nothing
      # would have failed. A bounded range is only as trustworthy as its bound.
      base, head = evidence["commit_range"].split("..")
      sha!(base, "commit_range base")
      sha!(head, "commit_range endpoint")

      [["base", base], ["endpoint", head]].each do |label, sha|
        expect(git!("cat-file", "-t", sha)).to eq("commit"), "commit_range #{label} #{sha} is not a commit"
        expect(git("merge-base", "--is-ancestor", sha, "HEAD").last).to be(true),
               "commit_range #{label} #{sha} is not reachable from HEAD"
      end

      expect(git("merge-base", "--is-ancestor", base, head).last).to be(true),
             "commit_range endpoint #{head} does not follow its base #{base}"
    end

    it "declares the same accepted paths in the state file and the acceptance record" do
      evidence["acceptance_diff_paths"].each do |path|
        expect(report).to include(path), "acceptance record omits declared path #{path}"
      end
    end

    it "cites only file paths that resolve" do
      # The directory list is READ FROM THE REPOSITORY rather than hardcoded. The previous form
      # named six directories, so a citation under `automation/` or `architecture/` — both of which
      # this tranche's records cite — matched nothing and was never checked. A hardcoded vocabulary
      # in a spec whose purpose is to catch hardcoded vocabularies is the same defect twice.
      dirs = ROOT.children.select(&:directory?).map { |d| d.basename.to_s } - %w[. .. .git tmp log node_modules]
      pattern = /`((?:#{dirs.map { |d| Regexp.escape(d) }.join('|')})\/[\w.\/-]+)`/
      cited = report.scan(pattern).flatten.uniq
      expect(cited).not_to be_empty, "no path citations found — has the record's format changed?"

      cited.each do |path|
        expect(ROOT.join(path)).to exist, "acceptance record cites #{path}, which does not exist"
      end
    end

    it "cites only Ruby identifiers that resolve, and FAILS on one that does not" do
      # The previous form skipped every unresolvable constant, and the record cites in the
      # repository's abbreviated style — so `safe_constantize` returned nil for all of them and the
      # check validated nothing. `HostGate#claimm` passed. Unresolved is now a FAILURE, and the
      # record has been changed to cite fully-qualified names so the check has something to bite on.
      citations = report.scan(/`([A-Z]\w+(?:::\w+)*)#(\w+)`/).uniq
      expect(citations).not_to be_empty, "no identifier citations found — has the record's format changed?"

      citations.each do |const, method|
        klass = const.safe_constantize
        expect(klass).not_to be_nil,
                             "acceptance record cites #{const}##{method}; #{const} does not resolve. " \
                             "Cite the fully-qualified constant."
        expect(klass.instance_methods(false) + klass.private_instance_methods(false))
          .to include(method.to_sym), "acceptance record cites #{const}##{method}, which does not exist"
      end
    end

    it "cites only migrations that exist" do
      # Migration basenames carry no path prefix, so the file-path check never saw them.
      names = report.scan(/`(\d{14}_\w+)`/).flatten.uniq
      expect(names).not_to be_empty, "no migration citations found — has the record's format changed?"
      names.each do |name|
        expect(ROOT.join("db/migrate/#{name}.rb")).to exist,
                                                      "acceptance record cites migration #{name}, which does not exist"
      end
    end

    it "agrees with the state file about the verified suite size" do
      # Parses the record's ACTUAL row — `| `bundle exec rspec` | `1871 examples, 0 failures` |`.
      # The previous regex targeted a table format the record-surface reduction had already
      # replaced, so it matched nothing and `next`ed past its own assertion.
      report_count = report[/\|\s*`bundle exec rspec`\s*\|\s*`(\d+) examples/, 1]
      state_count = BUILD_STATE["reconciliation_note"][/rspec (\d+)\/0/, 1]

      expect(report_count).not_to be_nil, "the record's rspec verification row did not parse"
      expect(state_count).not_to be_nil, "the state file records no rspec figure"
      expect(report_count).to eq(state_count),
                             "record says #{report_count} examples, state file says #{state_count}"
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
