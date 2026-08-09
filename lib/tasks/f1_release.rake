# frozen_string_literal: true

require "json"

# The owner-approval release service's invocation surface.
#
# IT IS A TASK AND NOT A ROUTE, DELIBERATELY. WORKFLOW_SPECIFICATIONS.md :168 denies
# `measurement_set.activate` to every human role and reserves it for the owner-approval release
# service, so there is no controller action, no route and nothing a browser can reach —
# `config/routes.rb` records the same decision at the other end. What can activate a Measurement Set
# is an operator running this task with bytes two owners have signed.
#
# NOTHING HERE SIGNS ANYTHING. The task reads a package that already carries both signatures and
# hands it to `Workflows::Wf006::OwnerApprovalRelease`, which recomputes the digest from the bytes it
# was given and refuses unless both signatures cover exactly that value. A package this task can
# activate is one the owners had already approved before it ran.
namespace :f1 do
  namespace :release do
    desc "Show what activating a signed Measurement Set package WOULD do, without doing it"
    task :plan_measurement_set, [:path] => :environment do |_task, args|
      package = F1Release.load!(args[:path])
      digest = Workflows::Wf006::MeasurementPackage.digest(package).unpack1("H*")
      signers = Workflows::Wf006::MeasurementPackage::SIGNERS.map do |signer|
        signature = package.dig("signatures", signer)
        "#{signer}=#{signature ? signature['decision'] : 'ABSENT'}"
      end

      puts "[f1:release:plan_measurement_set] #{args[:path]}"
      puts "  set            #{package['measurement_set_id']} v#{package['measurement_set_version']} " \
           "(#{package['measurement_kind']})"
      puts "  organization   #{package['organization_id']}"
      puts "  package_sha256 #{digest}"
      puts "  signatures     #{signers.join(', ')}"
      puts "  approval       #{package['owner_approval_reference']}"
      puts "  NOTHING WAS ACTIVATED. Run f1:release:activate_measurement_set to act on this."
    end

    desc "Activate a signed Measurement Set package as the owner-approval release service"
    task :activate_measurement_set, [:path] => :environment do |_task, args|
      package = F1Release.load!(args[:path])
      result = Workflows::Wf006::OwnerApprovalRelease.new.call(
        package:, organization_id: package["organization_id"], now: Time.now.utc,
        correlation_id: SecureRandom.uuid_v7
      )

      if result.success?
        payload = result.payload
        puts "[f1:release:activate_measurement_set] ACTIVE #{payload[:measurement_set_id]} " \
             "v#{payload[:measurement_set_version]} at #{payload[:activated_at]} " \
             "(approval #{payload[:owner_approval_reference]}, replayed=#{result.replayed})"
      else
        abort "[f1:release:activate_measurement_set] REFUSED #{result.reason_code} — nothing was activated"
      end
    end
  end
end

# Kept out of app/ autoload, in the shape `F1DbProvision` already establishes for task helpers.
module F1Release
  module_function

  def load!(path)
    raise ArgumentError, "usage: rake 'f1:release:activate_measurement_set[path/to/signed-package.json]'" if path.to_s.empty?

    JSON.parse(File.read(path))
  end
end
