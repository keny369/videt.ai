# frozen_string_literal: true

# The `project-profile-v1` body both Project-creation paths require (API_CONTRACTS.md
# :371 `ProjectProfile`; WORKFLOW_SPECIFICATIONS.md :621 "WF-002 first-Project body",
# :657 its exact shape).
#
# Most fixtures bootstrap a tenant only in order to exercise some LATER workflow, and
# there is exactly one valid shape for the body they must supply. Building it in one
# place keeps a fixture from quietly asserting a local-presence claim it never meant to
# make, and keeps the 30-odd bootstrap fixtures from drifting apart.
#
# The default is the declared-false branch: applicability false, a stated reason, and a
# null Local Business Profile. Specs that are ABOUT applicability state their own body
# rather than calling this.
module GenesisProjectProfile
  module_function

  DEFAULT_REASON = "Fixture project for an online-only trader with no premises customers visit."

  def body(display_name = "Genesis Site", reason: DEFAULT_REASON)
    {
      "project_profile_schema_version" => "project-profile-v1",
      "display_name" => display_name,
      "default_locale" => "en-AU",
      "reporting_time_zone" => "UTC",
      "objective" => "discoverability_assessment",
      "local_presence_applicable" => false,
      "local_presence_reason" => reason,
      "local_business_profile" => nil
    }
  end
end
