# frozen_string_literal: true

module App
  # WEB-005 `/app/access-unavailable` (FRONTEND_ARCHITECTURE.md :53): the deterministic
  # no-effective-access destination.
  #
  # A Session exists — sign-in succeeded — but it confers no effective access, so this
  # deliberately requires no capability and reads no product data. Gating it on a
  # permission would send an actor with no permissions into a redirect loop between here
  # and sign-in.
  class AccessController < ApplicationController
    def unavailable
      render :unavailable, status: :forbidden
    end
  end
end
