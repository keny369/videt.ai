# frozen_string_literal: true

require "rails_helper"

# THE SUITE'S OWN CONNECTIONS MUST BE BOUNDED.
#
# `config/database.yml` states the rule and the reason: "A conservative statement timeout keeps a
# contended lock in a test from hanging the suite." ActiveRecord applies it via `variables:`, so
# every pooled connection carries it. A raw `PG.connect` does not, and inherits the server default
# of `statement_timeout = 0` — unlimited.
#
# Both shared harness connections were raw, and `ReceiptMinter#truncate_all` runs the most
# lock-hostile statement in the suite from an `after` hook on nearly every acceptance example: a
# 26-table `TRUNCATE ... RESTART IDENTITY CASCADE`, needing ACCESS EXCLUSIVE on all of them. Behind
# any session holding ACCESS SHARE it waited forever and took the run with it — an unbounded hang,
# not a failure: no example named, no backtrace, killed from outside. Two of four whole-suite runs
# on one unchanged tree hung this way.
#
# These are cheap invariant checks rather than a live contention test, deliberately: proving the
# hang costs the timeout itself every run. The bound is what stops a lock from being unbounded, and
# the bound is what is asserted.
RSpec.describe "Test-harness connection bounds", type: :model do
  let(:configured) { ActiveRecord::Base.connection_db_config.configuration_hash.fetch(:variables, {}) }

  def timeout_of(conn) = conn.exec("SHOW statement_timeout").getvalue(0, 0)

  it "declares a statement timeout in database.yml at all" do
    # Everything below is only as strong as the configuration it reads. If the setting is ever
    # dropped, these checks would otherwise pass vacuously by comparing nothing to nothing.
    expect(configured["statement_timeout"].to_i).to be > 0
  end

  it "gives DbInspector's shared superuser connection a bounded statement timeout" do
    expect(timeout_of(DbInspector.connection)).not_to eq("0")
  end

  it "gives ReceiptMinter's shared schema-owner connection a bounded statement timeout" do
    # `truncate_all` is the statement that actually hung the suite.
    expect(timeout_of(ReceiptMinter.send(:owner_connection))).not_to eq("0")
  end

  it "writes only an allowlisted identifier into SET, never the configured string" do
    # `SET` takes an identifier, which cannot be parameterised, so the name is matched by equality
    # against a frozen list and the LIST'S element is what reaches the statement. Every variable
    # database.yml actually declares must be listed, or connections would raise on open.
    expect(PgTestConnection::PERMITTED).to be_frozen
    expect(configured.keys.map(&:to_s) - PgTestConnection::PERMITTED).to be_empty
  end

  it "REFUSES an unlisted session variable rather than silently skipping it" do
    # Skipping would recreate the defect this file exists to prevent: a harness connection quietly
    # running without a bound the application runs with.
    cfg = ActiveRecord::Base.connection_db_config.configuration_hash
    allow(ActiveRecord::Base).to receive(:connection_db_config)
      .and_return(instance_double(ActiveRecord::DatabaseConfigurations::HashConfig,
                                  configuration_hash: cfg.merge(variables: { "work_mem" => "64MB" })))

    expect { PgTestConnection.connect(user: cfg[:username].to_s) }
      .to raise_error(ArgumentError, /work_mem.*PERMITTED/m)
  end

  it "opens every MEMOIZED harness connection through PgTestConnection" do
    # The class of defect, not just its two instances — but scoped to the kind that is dangerous.
    # A process-wide memoized connection outlives every example and is shared by all of them, so an
    # unbounded wait on it stops the run. The two exempt files open a connection PER EXAMPLE and
    # close it in an `ensure`, and `race_harness` exists precisely to make connections block against
    # each other: bounding those would change deliberate concurrency semantics rather than protect
    # cleanup. Exemptions are named individually so a NEW memoized raw connection still fails.
    #
    # COMMENTS ARE STRIPPED BEFORE MATCHING. The first form of this check read raw source and so
    # flagged the very comment explaining why the call had been removed — a check that fails on its
    # own documentation is a check nobody will keep.
    per_example = %w[race_harness.rb scheduled_action_harness.rb pg_test_connection.rb]
    offenders = Rails.root.glob("spec/support/**/*.rb")
                    .reject { |f| per_example.include?(f.basename.to_s) }
                    .select { |f| f.readlines.map { |l| l.sub(/#.*/, "") }.any? { |l| l.match?(/\bPG\.connect\b/) } }
                    .map { |f| f.relative_path_from(Rails.root).to_s }

    expect(offenders).to be_empty,
                         "memoized harness files calling PG.connect directly (use PgTestConnection so " \
                         "database.yml's statement timeout applies): #{offenders.join(', ')}"
  end
end
