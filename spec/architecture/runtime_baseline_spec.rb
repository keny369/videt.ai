# frozen_string_literal: true

require "rails_helper"

# Proves the frozen runtime baseline (architecture/RAILS_APPLICATION_ARCHITECTURE.md)
# and the non-owner/forced-RLS runtime posture (schemas/POSTGRESQL_SCHEMA.md,
# TESTING_ARCHITECTURE.md) hold for the process the whole suite runs in.
RSpec.describe "Runtime baseline", type: :model do
  def scalar(sql) = ActiveRecord::Base.connection.select_value(sql)

  it "runs on PostgreSQL 17" do
    major = scalar("SELECT current_setting('server_version_num')::int / 10000")
    expect(major).to eq(17)
  end

  it "boots as the F1 application in UTC" do
    expect(Rails.application).to be_a(F1::Application)
    expect(Time.zone.name).to eq("UTC")
    expect(ActiveRecord.default_timezone).to eq(:utc)
  end

  it "connects as a non-owner runtime role in f1_runtime" do
    role = scalar("SELECT current_user")
    expect(role).to eq("f1_web")
    expect(scalar("SELECT pg_has_role(current_user, 'f1_runtime', 'MEMBER')")).to be(true)
  end

  it "never holds BYPASSRLS on the runtime connection" do
    bypass = scalar("SELECT rolbypassrls FROM pg_roles WHERE rolname = current_user")
    expect(bypass).to be(false)
  end

  it "owns no table on the runtime connection" do
    owned = scalar(<<~SQL)
      SELECT count(*) FROM pg_tables
      WHERE schemaname = 'public' AND tableowner = current_user
    SQL
    expect(owned).to eq(0)
  end
end
