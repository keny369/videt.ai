# frozen_string_literal: true

require "rails_helper"

# One resolution of a Crawl's operative limits (S-07-008; WORKFLOW_SPECIFICATIONS.md :390).
#
# The reason this is worth its own spec rather than being covered incidentally by the four call
# sites: S-07-008 makes the resolution CUSTOMER-VISIBLE. A limit decision records the configured
# value it was judged against, so "which policies contributed" stopped being an implementation
# detail and became something an event asserts to a customer.
RSpec.describe Workflows::Wf005::EffectiveLimits do
  subject(:limits) { described_class }

  let(:global) { Workflows::Wf005::CrawlPolicy::GLOBAL_CEILING }

  def policy_row(id:, version:, bounds:, digest: "ab" * 32)
    { "id" => id, "policy_version" => version, "scope" => "organization",
      "normalized_bounds" => JSON.generate(bounds), "content_sha256" => digest }
  end

  def narrowed(dimension, soft:, hard:)
    global.merge(dimension => { "soft" => soft, "hard" => hard })
  end

  describe "the resolved bounds" do
    it "is the frozen global ceiling when no Organization or Project policy is active" do
      expect(limits.resolve([]).bounds).to eq(global)
    end

    it "takes the per-dimension MINIMUM, so a Project narrowing one dimension narrows only it" do
      resolution = limits.resolve([policy_row(id: SecureRandom.uuid_v7, version: "org-1",
                                              bounds: narrowed("crawl_depth", soft: 2, hard: 3))])

      expect(resolution.bounds["crawl_depth"]).to eq({ "soft" => 2, "hard" => 3 })
      expect(resolution.bounds["accepted_pages"]).to eq(global["accepted_pages"])
    end

    it "IGNORES a malformed stored policy rather than guessing at it" do
      row = policy_row(id: SecureRandom.uuid_v7, version: "org-1", bounds: { "crawl_depth" => "deep" })
      expect(limits.resolve([row]).bounds).to eq(global)
    end

    it "falls back to the global ceiling when the stored bounds are not JSON at all" do
      row = policy_row(id: SecureRandom.uuid_v7, version: "org-1", bounds: {}).merge("normalized_bounds" => "{oops")
      expect(limits.resolve([row]).bounds).to eq(global)
    end

    # FU-12(f). THE TWO TESTS ABOVE BOTH PASS ONE ROW, WHICH IS WHY THIS DEFECT SURVIVED THEM.
    #
    # `resolve`'s rescue was METHOD-WIDE, so an unparseable row did not merely fail to contribute —
    # it abandoned the whole resolution and returned the GLOBAL CEILING, discarding every valid
    # narrowing policy that had already been read or was still to come. With one row in the corpus
    # "ignored" and "abandoned the resolution" produce the same answer, and no example held more
    # than one.
    #
    # THE DIRECTION IS WHAT MAKES IT WORTH A PROOF: a malformed row belonging to one scope made the
    # limits of ANOTHER scope WIDER, and the event then named the global clamp as the only governing
    # version. Bad data must not buy a bigger crawl.
    context "when one stored policy is unreadable and another is valid (FU-12(f))" do
      let(:unparseable) do
        policy_row(id: SecureRandom.uuid_v7, version: "org-broken", bounds: {})
          .merge("normalized_bounds" => "{oops")
      end
      let(:valid) do
        policy_row(id: SecureRandom.uuid_v7, version: "proj-1",
                   bounds: narrowed("crawl_depth", soft: 2, hard: 3), digest: "cd" * 32)
      end

      it "keeps the valid narrowing when the unreadable policy is read FIRST" do
        resolution = limits.resolve([unparseable, valid])

        expect(resolution.bounds["crawl_depth"]).to eq({ "soft" => 2, "hard" => 3 })
        expect(resolution.versions).to include("proj-1")
      end

      it "keeps the valid narrowing when the unreadable policy is read LAST" do
        # BOTH ORDERS, because a method-wide rescue is order-blind and a per-row one must be too.
        resolution = limits.resolve([valid, unparseable])

        expect(resolution.bounds["crawl_depth"]).to eq({ "soft" => 2, "hard" => 3 })
        expect(resolution.versions).to include("proj-1")
      end

      it "still refuses to NAME the policy it could not read" do
        # The contributing set and the named set are the same set — the module's own rule, which the
        # per-row skip must not quietly break.
        expect(limits.resolve([unparseable, valid]).versions).not_to include("org-broken")
      end
    end
  end

  describe "definition_versions (API_CONTRACTS.md :713 EventGoverningVersion)" do
    it "always names the frozen global ceiling, with an identity derived from its own bytes" do
      entry = limits.resolve([]).definition_versions.sole

      expect(entry["artifact_type"]).to eq("global_crawl_safety")
      expect(entry["version"]).to eq(Workflows::Wf005::CrawlPolicy::GLOBAL_VERSION)
      expect(entry["content_sha256"]).to eq(Digest::SHA256.hexdigest(
                                              Platform::CanonicalJson.encode(
                                                Workflows::Wf005::CrawlPolicy.normalize(global)
                                              )
                                            ))
      # A `uuid`, and the SAME uuid on every call — a governing-version reference that changed per
      # process would name a different artifact in every event.
      expect(entry["artifact_id"]).to match(/\A\h{8}-\h{4}-8\h{3}-[89ab]\h{3}-\h{12}\z/)
      expect(entry["artifact_id"]).to eq(limits.resolve([]).definition_versions.sole["artifact_id"])
    end

    it "names every CONTRIBUTING policy, sorted and duplicate-free" do
      a = policy_row(id: "00000000-0000-7000-8000-0000000000aa", version: "org-1",
                     bounds: narrowed("crawl_depth", soft: 2, hard: 3), digest: "11" * 32)
      b = policy_row(id: "00000000-0000-7000-8000-0000000000bb", version: "proj-1",
                     bounds: narrowed("accepted_pages", soft: 10, hard: 20), digest: "22" * 32)

      entries = limits.resolve([b, a, a]).definition_versions

      # ":713 sorted by artifact type, ID, version, then digest" — artifact TYPE first, so the two
      # `crawl_policy` rows precede `global_crawl_safety` whatever order they arrived in, and the
      # duplicate collapses.
      expect(entries.map { |e| e["version"] })
        .to eq(["org-1", "proj-1", Workflows::Wf005::CrawlPolicy::GLOBAL_VERSION])
      expect(entries.map { |e| e["content_sha256"] }.first(2)).to eq(["11" * 32, "22" * 32])
      expect(entries.uniq.size).to eq(entries.size)
    end

    it "does NOT name a policy that was ignored for being malformed" do
      # The contributing set and the named set are the same set. If they can differ, an event can
      # report a configured value beside a policy that had no part in producing it — which is
      # exactly the drift the decision record exists to make impossible.
      good = policy_row(id: "00000000-0000-7000-8000-0000000000aa", version: "good",
                        bounds: narrowed("crawl_depth", soft: 2, hard: 3))
      bad = policy_row(id: "00000000-0000-7000-8000-0000000000bb", version: "bad",
                       bounds: { "crawl_depth" => "deep" })

      versions = limits.resolve([good, bad]).definition_versions.map { |e| e["version"] }
      expect(versions).to include("good")
      expect(versions).not_to include("bad")
    end

    it "RAISES when a reader forgot to select the digest, rather than silently clamping" do
      # The trap the four copies this replaced would have set: `KeyError` inside the rescue would
      # have discarded every Organization and Project policy and returned the global ceiling, with
      # no failure anywhere. A reader that does not select what an event needs must fail loudly.
      row = policy_row(id: SecureRandom.uuid_v7, version: "org-1",
                       bounds: narrowed("crawl_depth", soft: 2, hard: 3))
      row.delete("content_sha256")

      expect { limits.resolve([row]) }.to raise_error(KeyError)
    end
  end

  describe "the views the callers use" do
    it "converts MiB policy units into the bytes the fetch path enforces" do
      resolution = limits.resolve([])
      expect(resolution.byte_bounds.per_run).to eq(global["run_response_mib"]["hard"] * 1024 * 1024)
    end

    it "reports the configured value in the units a DECISION records" do
      resolution = limits.resolve([])
      # :442 requires the decision to carry "configured value" and "observed value"; the byte
      # dimensions are scaled so the pair is comparable.
      expect(resolution.configured("accounted_response_body_bytes_per_run", "hard"))
        .to eq(global["run_response_mib"]["hard"] * 1024 * 1024)
      expect(resolution.configured("wall_clock_run_duration", "hard"))
        .to eq(global["wall_clock_minutes"]["hard"])
    end
  end
end
