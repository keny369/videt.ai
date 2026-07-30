# frozen_string_literal: true

require "pg"

# The one place the suite opens a RAW PostgreSQL connection.
#
# `config/database.yml` carries a deliberate defence: "A conservative statement timeout keeps a
# contended lock in a test from hanging the suite." ActiveRecord applies it through the `variables:`
# block, so every pooled connection runs with it. A raw `PG.connect` does NOT — it inherits the
# server default, which is `statement_timeout = 0`, meaning UNLIMITED.
#
# Both shared harness connections were raw, and one of them (`ReceiptMinter#truncate_all`) issues
# the single most lock-hostile statement in the suite: `TRUNCATE` over 26 tables with
# `RESTART IDENTITY CASCADE`, from an `after` hook that runs on essentially every acceptance
# example. TRUNCATE needs ACCESS EXCLUSIVE on every table it names, so it waits behind any session
# holding so much as ACCESS SHARE — and with no statement timeout it waits FOREVER, taking the whole
# suite with it. That is an unbounded hang rather than a failure: no example is named, no backtrace
# is produced, and the run has to be killed from outside.
#
# Demonstrated rather than assumed. With one session idle in a transaction that has merely SELECTed
# from `organizations`, `TRUNCATE organizations CASCADE` on a harness-style connection was still
# blocked after 20 seconds; the identical statement on the same kind of connection carrying
# `database.yml`'s 15s value raised `PG::QueryCanceled`.
#
# So the timeout is not WIDENED here and no test is serialised or slowed to hide a race. A bound is
# introduced where there was none, from the repository's own configuration rather than a literal, so
# the harness cannot drift away from the value the application runs under. A contended lock now
# fails loudly, naming its statement, which is exactly what `database.yml` says the setting is for.
module PgTestConnection
  module_function

  # The session variables this helper will carry, as an ALLOWLIST.
  #
  # `SET` takes an identifier, and an identifier cannot be parameterised or escaped as a literal —
  # so the earlier form interpolated the configured NAME straight into SQL and escaped only the
  # value. The configuration is repository-controlled and this is test-only code, so it was not
  # reachable; it was still an identifier built from input, which is not a thing to leave in place
  # because the current input happens to be trusted.
  #
  # The name written into the statement below is therefore an element of THIS frozen array, matched
  # by equality, never the string that came from the file.
  PERMITTED = %w[statement_timeout lock_timeout idle_in_transaction_session_timeout].freeze

  # Connect as `user`, carrying every session variable `database.yml` declares.
  #
  # An unlisted variable RAISES rather than being skipped. Skipping would silently recreate the
  # exact defect this file exists to prevent: a harness connection quietly running without a bound
  # the application runs with. Adding a variable to `database.yml` that belongs on these connections
  # is a one-line change here, and the failure says so.
  def connect(user:)
    cfg = ActiveRecord::Base.connection_db_config.configuration_hash
    conn = PG.connect(host: cfg[:host], port: cfg[:port], dbname: cfg[:database], user:)
    cfg.fetch(:variables, {}).each do |name, value|
      permitted = PERMITTED.find { |allowed| allowed == name.to_s }
      if permitted.nil?
        conn.close
        raise ArgumentError,
              "database.yml declares session variable #{name.inspect}, which PgTestConnection::PERMITTED " \
              "does not list. Add it there if harness connections should carry it."
      end
      conn.exec("SET #{permitted} = #{conn.escape_literal(value.to_s)}")
    end
    conn
  end
end
