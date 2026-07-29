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

  # Connect as `user`, carrying every session variable `database.yml` declares.
  def connect(user:)
    cfg = ActiveRecord::Base.connection_db_config.configuration_hash
    conn = PG.connect(host: cfg[:host], port: cfg[:port], dbname: cfg[:database], user:)
    cfg.fetch(:variables, {}).each { |name, value| conn.exec("SET #{name} = #{conn.escape_literal(value.to_s)}") }
    conn
  end
end
