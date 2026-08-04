# frozen_string_literal: true

require "rails_helper"
require "json"
require "yaml"
require "open3"
require_relative "../../automation/lib/autonomous_build/frozen_contracts"

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

  # THE RECORD UNDER REVIEW, CHECKED WHILE IT IS UNDER REVIEW (round 6, R6-9).
  #
  # THE STRUCTURAL GAP THIS CLOSES, which is the reason R6-9 exists at all. Every check above binds
  # `acceptance_evidence.block` — the last ACCEPTED tranche. S-07-009 is not accepted, so
  # `S-07-009_COMPLETION_REPORT.md` was validated by nothing for the entire period in which five
  # review rounds were reading it, and the record-defect blockers accumulated in exactly that blind
  # spot: R4-8, R5-4, R5-5, R6-8 and R6-9 are all one class, and all five are statements about the
  # repository that the repository could have refuted mechanically.
  #
  # THIS BLOCK BINDS `current_tranche` INSTEAD. It runs whether or not the tranche is accepted, so a
  # false claim is caught by the gate that authored it rather than by the round after it.
  describe "the record of the tranche currently under review" do
    let(:in_flight_path) { ROOT.join("#{BUILD_STATE.fetch('current_tranche')}_COMPLETION_REPORT.md") }
    let(:in_flight) do
      skip "#{in_flight_path.basename} does not exist yet" unless in_flight_path.exist?
      in_flight_path.read
    end

    # A row of the report's proof table: the spec file, and the number of distinct `PROOF n`
    # identifiers it claims. The report defines the count that way in its own prose, so the check
    # measures the thing the report says it is reporting.
    def proof_rows(text) = text.scan(/^\|\s*`(spec\/[^`]+)`\s*\|\s*(\d+)\s*\|/)

    def distinct_proof_ids(path) = ROOT.join(path).read.scan(/PROOF\s+(\d+[a-z]*)/).flatten.uniq

    it "derives every proof count from the file it names, rather than restating a maintained number" do
      # R6-9: the report claimed 13 for a file containing 16, the round-4 review recorded the
      # discrepancy, the R5-5 rewrite kept it, and round 6 promoted it to a blocker. A number a human
      # maintains beside a file that changes is a number that will disagree with it; this makes the
      # disagreement a gate failure instead of a review finding.
      rows = proof_rows(in_flight)
      expect(rows).not_to be_empty, "the report's proof table did not parse — has its format changed?"

      rows.each do |path, claimed|
        expect(ROOT.join(path)).to exist, "the report's proof table names #{path}, which does not exist"
        actual = distinct_proof_ids(path)
        expect(actual.length).to eq(claimed.to_i),
                                 "#{path}: the report says #{claimed} distinct PROOF identifiers, " \
                                 "the file contains #{actual.length} (#{actual.sort_by(&:to_i).join(', ')})"
      end
    end

    # ---- what round 8 proved prose cannot be trusted to carry (R8-7) -----------------------------
    #
    # THE RECORD STATED FALSEHOODS ABOUT ITSELF AND EVERY LIMB ABOVE PASSED. The Identity table pinned
    # a two-rounds-stale candidate and authority while the prose above it described a later round; the
    # round count disagreed with itself between two paragraphs; the suite figure disagreed with the
    # measured one and with `BUILD_STATE`, three records and three numbers; and "the only frozen-path
    # change in the tranche" was written where `FrozenContracts.frozen_changes` returns two.
    #
    # THE SUITE-SIZE LIMB WAS THE SHAPE OF THE WHOLE PROBLEM. It compared the report to the state file
    # — two records, to each other — which is exactly the "restating a maintained number" failure R6-9
    # named, one level up: both could be, and were, wrong together. It now compares them to a
    # MEASUREMENT.

    # The suite's real size, counted by RSpec rather than remembered. `--dry-run` loads every spec file
    # and reports what would run without running it, so this is a measurement and not a second record.
    def measured_suite_size
      @measured_suite_size ||= begin
        out, = Open3.capture2e({ "RAILS_ENV" => "test" }, "bundle", "exec", "rspec", "--dry-run",
                               chdir: ROOT.to_s)
        out[/(\d+) examples?/, 1]&.to_i
      end
    end

    it "agrees with a MEASUREMENT of the suite, not merely with the other record" do
      claimed = in_flight[/\|\s*`bundle exec rspec`\s*\|\s*`(\d+) examples/, 1]
      state = BUILD_STATE["next_action"][/rspec (\d+)\/0/, 1]

      expect(claimed).not_to be_nil, "the record's rspec verification row did not parse"
      expect(measured_suite_size).not_to be_nil, "rspec --dry-run reported no example count"
      expect(claimed.to_i).to eq(measured_suite_size),
                              "the record claims #{claimed} examples; rspec counts #{measured_suite_size}"
      expect(state.to_i).to eq(measured_suite_size),
                            "BUILD_STATE claims #{state} examples; rspec counts #{measured_suite_size}"
    end

    it "pins the same candidate range in the record and the state file" do
      # R8-7: `:34` pinned `7f043a2..4e2d8cf` — the round-6 value — while `:3` and `:14` described
      # round 7, so a reviewer following the Identity table reviews the wrong range.
      record_range = in_flight[/\*\*Repair candidate\*\*\s*\|\s*\*\*`([0-9a-f]+\.\.[0-9a-f]+)`/, 1]
      state_range = BUILD_STATE["next_action"][/([0-9a-f]{7,40}\.\.[0-9a-f]{7,40})/, 1]

      expect(record_range).not_to be_nil, "the record's Identity table names no pinned candidate range"
      expect(state_range).not_to be_nil, "BUILD_STATE.next_action names no candidate range"
      expect(record_range).to eq(state_range),
                             "record pins #{record_range}, state file pins #{state_range}"
      base, head = record_range.split("..")
      expect(git("merge-base", "--is-ancestor", base, head).last).to be(true),
                                                                    "#{base} is not an ancestor of #{head}"
      expect(git("merge-base", "--is-ancestor", head, "HEAD").last).to be(true),
                                                                      "#{head} is not reachable from HEAD"
    end

    it "counts the review rounds the same way the review record does" do
      # R8-7: ":204 says 'six rounds, six FAILs' against :5's 'Seven full ADR-026 five-lens rounds'."
      # The number of rounds is not a matter of recollection: the review record has one heading each.
      review = ROOT.join("S-07-009_ACCEPTANCE_REVIEW.md").read
      rounds = review.scan(/^# ROUND (\d+)/).flatten.map(&:to_i)
      expect(rounds).to eq((1..rounds.length).to_a), "the review record's round headings are not 1..n"

      in_flight.scan(/(\w+|\d+) (?:full )?(?:ADR-026 )?(?:five-lens )?rounds/i).flatten.each do |claim|
        numeric = claim.to_i.positive? ? claim.to_i : NUMBER_WORDS[claim.downcase]
        next if numeric.nil?

        expect(numeric).to eq(rounds.length),
                           "the record says #{claim} rounds; the review record contains #{rounds.length}"
      end
    end

    NUMBER_WORDS = { "one" => 1, "two" => 2, "three" => 3, "four" => 4, "five" => 5, "six" => 6,
                     "seven" => 7, "eight" => 8, "nine" => 9, "ten" => 10 }.freeze

    it "counts frozen-path changes the way FrozenContracts counts them" do
      # R8-7: ":162 claims the detector spec is 'the only frozen-path change in the tranche' where
      # `FrozenContracts.frozen_changes` on the candidate diff returns TWO."
      range = in_flight[/\*\*Repair candidate\*\*\s*\|\s*\*\*`([0-9a-f]+\.\.[0-9a-f]+)`/, 1]
      skip "no pinned candidate range" if range.nil?

      changed = git!("diff", "--name-only", range).lines.map(&:strip).reject(&:empty?)
      frozen = AutonomousBuild::FrozenContracts.frozen_changes(changed)
      claimed = in_flight[/(\w+) frozen-path changes?/i, 1]
      skip "the record makes no numeric frozen-path claim" if claimed.nil?

      numeric = claimed.to_i.positive? ? claimed.to_i : NUMBER_WORDS[claimed.downcase]
      expect(numeric).to eq(frozen.length),
                         "the record claims #{claimed} frozen-path change(s); the candidate diff has " \
                         "#{frozen.length}: #{frozen.join(', ')}"
    end

    # ---- mutation evidence, which may not be inferred (R8-7, and FU-44's re-derivation) ------------
    #
    # ROUND 8's FU-44 RECORDED A SURVIVOR FROM A SUBSTITUTION THAT WAS NEVER VERIFIED APPLIED. The
    # file holds THREE identical `if now >= effective_deadline(r)` comparisons and an unscoped
    # replacement lands on the first, which is not the site the follow-up named. A record that says "X
    # survives" while the mutation never reached X is worse than silence, because the next round
    # spends itself on a defect that does not exist.
    #
    # So a mutation claim is now backed by a LEDGER the harness writes, entry by entry, and no entry
    # can exist without confirmation that the mutation landed — the harness aborts rather than record
    # a verdict for an edit git cannot see.
    LEDGER_PATH = "specification/automation/S-07-009_MUTATION_LEDGER.json"

    it "backs every mutation claim with a ledger entry that confirms the mutation LANDED" do
      skip "no mutation ledger in this tranche" unless ROOT.join(LEDGER_PATH).exist?

      ledger = JSON.parse(ROOT.join(LEDGER_PATH).read).fetch("mutations")
      expect(ledger).not_to be_empty

      ledger.each do |entry|
        expect(entry["landed"]).to be(true),
                                   "#{entry['id']} is recorded with no confirmation that it landed"
        expect(entry["restored"]).to eq("true true"),
                                     "#{entry['id']} did not restore the worktree exactly"
        expect(entry["verdict"]).to eq(entry["expectation"] == "kill" ? "killed" : "survived"),
                                    "#{entry['id']} is expected to be #{entry['expectation']} and was " \
                                    "#{entry['verdict']}"
        # A SURVIVOR MAY NOT BE EXCUSED SILENTLY. An entry that expects survival carries the reason the
        # mutant is equivalent, or the ledger becomes a way of recording any survivor as intended.
        unless entry["expectation"] == "kill"
          expect(entry["equivalence_reason"].to_s.length).to be > 200,
                                                             "#{entry['id']} expects survival and records " \
                                                             "no reason the mutant is equivalent"
        end
        expect(entry["result"]).to match(/\d+ examples?, \d+ failures?/),
                                   "#{entry['id']} records no example/failure counts"
        spec = entry["command"][/rspec (\S+)/, 1]
        expect(ROOT.join(spec)).to exist, "#{entry['id']} names #{spec}, which does not exist"
        next unless entry["verdict"] == "killed"

        expect(entry["failing_examples"]).not_to be_empty,
                                                 "#{entry['id']} is recorded killed but names no failing example"
      end
    end

    it "names in the record only mutations the ledger actually ran" do
      skip "no mutation ledger in this tranche" unless ROOT.join(LEDGER_PATH).exist?

      ids = JSON.parse(ROOT.join(LEDGER_PATH).read).fetch("mutations").map { |m| m["id"] }
      cited = in_flight.scan(/`(m\d[\w-]*|fu44[\w-]*|a\d-[\w-]*)`/).flatten.uniq
      expect(cited).not_to be_empty, "the record cites no mutation identifiers"
      expect(cited - ids).to be_empty,
                             "the record names mutations the ledger does not contain: #{(cited - ids).join(', ')}"
    end

    it "cites only file paths and migrations that resolve" do
      dirs = ROOT.children.select(&:directory?).map { |d| d.basename.to_s } - %w[. .. .git tmp log node_modules]
      pattern = /`((?:#{dirs.map { |d| Regexp.escape(d) }.join('|')})\/[\w.\/-]+)`/
      cited = in_flight.scan(pattern).flatten.uniq
      expect(cited).not_to be_empty, "no path citations found — has the record's format changed?"
      cited.each do |path|
        expect(ROOT.join(path)).to exist, "the report under review cites #{path}, which does not exist"
      end

      migrations = in_flight.scan(/`(\d{14}_\w+)`/).flatten.uniq
      migrations.each do |name|
        expect(ROOT.join("db/migrate/#{name}.rb")).to exist,
                                                      "the report under review cites migration #{name}, " \
                                                      "which does not exist"
      end
    end

    # R6-8: ADR-117 says it "records that authority BEFORE IMPLEMENTATION", and git says otherwise —
    # the ADR is absent from the parent of `f7472aa`, the commit that implemented `Platform::PgInstant`,
    # and first appears in `5860bb4` alongside the repairs it authorizes.
    #
    # AUTONOMOUS_BUILD_CONTROLLER §3.1 is why that is a defect rather than a quibble: "the controller
    # must derive work from versioned repository files, not conversational memory. CHAT SESSIONS ARE
    # NOT AUTHORITATIVE STATE." A ruling given in conversation and committed afterwards is a perfectly
    # ordinary thing; a RECORD claiming the repository shows an order the repository does not show is
    # the one thing that rule forbids, because the next reader has only the repository.
    it "makes no ADR claim about commit order that git refutes" do
      decisions = ROOT.join("DECISIONS.md").read
      expect(decisions).not_to match(/records that authority \*\*before implementation\*\*/i),
                               "an ADR claims to precede an implementation it does not precede in git"
    end
  end

  # THE REFUTATION CANNOT DRIFT BACK, AND IT CANNOT HIDE IN A PLACE NOBODY LISTED (FU-36, ADR-115).
  #
  # ADR-097 recorded that a NULL-safe rewrite of `crawls_coverage_status_check` using
  # `IS NOT DISTINCT FROM` was "a proven no-op, evaluated against the live cluster". It is the
  # opposite: the `ANY(...)` form is a PostgreSQL syntax error and the pairwise form yields FALSE,
  # which a CHECK REFUSES — it would reject every `queued` and `running` Crawl. PROOF 104 pins the
  # four evaluations against the live cluster.
  #
  # ADR-111 corrected five places BY HAND and missed a sixth (ADR-083); round 2 found that one, and
  # the FU-36 repository sweep then found a SEVENTH that no review had named (`BUILD_PLAN.yml`). A
  # defect whose whole content is "a ratified record states the opposite of the truth" is not closed
  # by correcting the copies someone happened to list — the same shape of mistake as PROOF 39
  # enumerating the foreign keys that exist. This asserts over the RECORDS THEMSELVES, so an eighth
  # copy fails CI instead of waiting for a reviewer to read it.
  #
  # THE UNIT IS A WINDOW AROUND THE CLAIM, NOT THE SECTION, AND THE FIRST VERSION OF THIS CHECK GOT
  # THAT WRONG. Scoped to the section, reverting ADR-083 to its false wording still PASSED, because
  # that ADR is long and carries refutation-shaped words about unrelated matters — the check would not
  # have caught the very defect it exists for, which is PROOF 39's mistake in a third costume. The
  # refutation has to be where the reader meets the claim, so it is required within the surrounding
  # `WINDOW` characters. Every correct record states the false claim in order to refute it, and every
  # one of them carries the refutation within a few hundred characters of it.
  describe "no authoritative record claims the refuted PostgreSQL predicate is harmless" do
    # THE CORPUS IS DERIVED, BECAUSE A HAND LIST IS THE DEFECT THIS CHECK EXISTS FOR (round 3, R3-7).
    #
    # The first version enumerated six files. That is PROOF 39's mistake in a fourth costume, and the
    # header above says so in as many words while doing it: a defect whose content is "a ratified
    # record states the opposite of the truth" cannot be closed by checking the copies someone
    # happened to list. It had ALREADY missed one — `S-07-008_COMPLETION_REPORT.md`, a record that
    # exists today — and it could not see `S-07-009_COMPLETION_REPORT.md`, the file this tranche's own
    # acceptance will create. A check that must be edited whenever a record is added is a reminder,
    # not a control.
    #
    # `git ls-files` rather than a glob: the corpus is what the repository TRACKS, so an untracked
    # scratch file cannot fail CI and a newly tracked record is covered the moment it is committed.
    def predicate_records
      out = `git -C #{ROOT} ls-files -z`
      raise "git ls-files failed; the corpus cannot be derived" unless $CHILD_STATUS.success?

      out.split("\0").reject(&:empty?).select { |p| p.match?(/\.(md|ya?ml|json|rb|sql)\z/) }
         .reject { |p| p.match?(%r{\A(vendor|node_modules|tmp)/}) }
         # This file states the claim and the harmless words in order to define them.
         .reject { |p| p == "spec/architecture/repository_truth_spec.rb" }
    end

    CLAIM = /IS NOT DISTINCT FROM/i
    HARMLESS = /no-op|admitted|yields true/i
    # `refut` covers the records that state the claim in order to correct it and put the evaluation a
    # little further down the page than `WINDOW` reaches — the review record's own R2-B3 finding and
    # the FU-36 note both do exactly that.
    # `refuse` unstemmed, so "would REFUSE every live Crawl" counts — PROOF 104's own title, which the
    # narrower `refuses` did not match and which the widened corpus therefore reported as an offender.
    REFUTED = /syntax error|refuse|reject every|not a no-op|is not admitted|-> +f\b|yields false|refut/i
    # `20260727120280_crawl_limit_decision_reason_null_safe` uses `IS NOT DISTINCT FROM` CORRECTLY,
    # and for exactly the property this refutation turns on: a NULL yields FALSE, which the CHECK
    # refuses.
    #
    # EXEMPTED BY PATH, NOT BY NEARBY WORDS (round 3, R3-7). This was `/crawl_limit_decision|
    # limit_reached/i` matched against the WINDOW, and `limit_reached` is S-07-009's OWN COMPLETION
    # REASON — a token that appears throughout this tranche's records, its migrations and its ADRs.
    # Any false claim written within 700 characters of it was therefore exempt, which is most of the
    # places a false claim about this tranche would actually be written. The correct use is a
    # PROPERTY OF ONE FILE and is now named as one.
    CORRECT_USE_PATHS = %w[
      db/migrate/20260727120280_crawl_limit_decision_reason_null_safe.rb
      spec/persistence/crawl_limit_decision_invariants_spec.rb
    ].freeze

    # The correct use is also DESCRIBED in records that are not those files — S-07-008's completion
    # report tabulates that migration and says its old form "admitted a NULL reason", which is true of
    # `crawl_limit_decisions` and says nothing about `crawls_coverage_status_check`. So the subject is
    # still exempted by window, but by the token that NAMES THE OTHER CONSTRAINT and nothing else.
    # `limit_reached` is gone: it is S-07-009's own completion reason, it appears throughout this
    # tranche's records, and exempting every claim written within 700 characters of it exempted most
    # of the places a false claim about this tranche would be written.
    CORRECT_USE_SUBJECT = /crawl_limit_decision/i

    # Wide enough for a claim and a fenced four-line evaluation below it; narrow enough that an
    # unrelated "refuses" elsewhere in a long ADR cannot vouch for it.
    WINDOW = 700

    # The guard on the corpus itself. A derivation that silently returned nothing — a failed `git`, a
    # tightened extension list — would make the example below vacuously green, which is precisely the
    # class of defect this whole file exists to catch.
    it "derives a corpus that contains the records known to state the claim" do
      records = predicate_records
      expect(records.size).to be > 100
      expect(records).to include("DECISIONS.md", "schemas/POSTGRESQL_SCHEMA.md",
                                 "specification/automation/BUILD_PLAN.yml",
                                 "specification/automation/BUILD_STATE.json",
                                 "S-07-008_COMPLETION_REPORT.md")
      # The records that actually carry the claim today, found rather than listed.
      carriers = records.select { |p| ROOT.join(p).file? && ROOT.join(p).read.match?(CLAIM) }
      expect(carriers.size).to be >= 10
    end

    it "carries no claim that the rewrite is a no-op or admitted, unrefuted where it is made" do
      offenders = (predicate_records - CORRECT_USE_PATHS).flat_map do |path|
        file = ROOT.join(path)
        next [] unless file.file?

        body = file.read
        next [] unless body.match?(CLAIM)

        body.enum_for(:scan, CLAIM).map { Regexp.last_match.begin(0) }.filter_map do |at|
          window = body[[at - WINDOW, 0].max, WINDOW * 2].to_s
          next unless window.match?(HARMLESS)
          next if window.match?(REFUTED) || window.match?(CORRECT_USE_SUBJECT)

          "#{path} @#{at}: #{body[at, 200].strip}"
        end
      end

      expect(offenders).to be_empty, <<~MSG
        A record claims the `IS NOT DISTINCT FROM` rewrite of `crawls_coverage_status_check` is
        harmless. It is not: the `ANY(...)` form is a PostgreSQL syntax error and the pairwise form
        yields FALSE, which a CHECK refuses, so it would reject every `queued` and `running` Crawl.
        See DECISIONS ADR-111 / ADR-115 and PROOF 104.

        #{offenders.join("\n\n")}
      MSG
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
