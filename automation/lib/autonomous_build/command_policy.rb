# frozen_string_literal: true

module AutonomousBuild
  # Command allowlist / prohibited-operation enforcement (mandate §8.3; AUTONOMY_POLICY command
  # policy). Every command the controller is about to execute — verification commands from the
  # manifest and any agent-proposed command — passes through here first. A prohibited command is
  # never run; it raises PolicyViolation, which the controller surfaces as a `policy_violation`
  # terminal state. This is a denylist of dangerous shapes plus an allowlist gate for the commands
  # the controller itself issues.
  module CommandPolicy
    module_function

    # Dangerous command shapes that must never execute.
    PROHIBITED = {
      "recursive root/home deletion" => /\brm\s+(-[A-Za-z]*\s+)*-?[rR][fF]?\b.*\s(\/|~|\$HOME)(\s|\z)/,
      "disk formatting" => /\bmkfs(\.\w+)?\b/,
      "raw disk write" => /\bdd\s+.*\bof=\/dev\//,
      "fork bomb" => /:\s*\(\s*\)\s*\{.*\}\s*;\s*:/,
      "force push" => /\bgit\s+push\b.*(--force\b|--force-with-lease\b|\s-f\b)/,
      "history rewrite" => /\bgit\s+(rebase\b|filter-branch\b|filter-repo\b)|\bgit\s+push\b.*--mirror\b/,
      "protected-branch reset" => /\bgit\s+reset\s+--hard\s+\S*(main|master|origin\/)/,
      "protected-branch checkout-force" => /\bgit\s+checkout\s+.*-f\b.*(main|master)/,
      "broad process termination" => /\b(killall\b|pkill\s+-9\b|kill\s+-9\s+-1\b)/,
      "system shutdown" => /\b(shutdown|reboot|halt|poweroff)\b/,
      "production rails env" => /\bRAILS_ENV=production\b/,
      "production migration" => /\bproduction\b.*\bdb:(migrate|drop|reset|schema:load)\b/,
      "database drop/reset" => /\bdb:(drop|reset)\b/,
      "permission bypass" => /(--dangerously-skip-permissions|--permission-mode(=|\s+)bypassPermissions|sudo\s)/,
      "pipe-to-shell" => /\b(curl|wget)\b[^\n|]*\|\s*(sudo\s+)?(sh|bash|zsh)\b/,
      "arbitrary outbound upload" => /\b(curl|wget)\b.*\s(-T|--upload-file|--data-binary\s+@)/,
      "secret store inspection" => /\b(security\s+find-generic-password|cat\s+.*\.env\b|printenv\b.*(KEY|SECRET|TOKEN))/i
    }.freeze

    # Command prefixes the controller itself is permitted to run (verification, git inspection,
    # scoped provider CLIs). Agent-proposed commands outside this set are gated by the denylist and,
    # when strict, must match an allowed prefix.
    ALLOWED_PREFIXES = [
      "bundle exec ", "bin/", "git status", "git rev-parse", "git worktree", "git diff", "git log",
      "git add", "git commit", "git checkout -b", "git switch -c", "git branch", "git stash",
      "git show", "git ls-files", "git symbolic-ref"
    ].freeze

    class ProhibitedCommand < PolicyViolation; end

    def prohibited_reason(command)
      cmd = command.to_s
      PROHIBITED.each { |reason, pattern| return reason if cmd.match?(pattern) }
      nil
    end

    def prohibited?(command) = !prohibited_reason(command).nil?

    def allowed_prefix?(command)
      ALLOWED_PREFIXES.any? { |prefix| command.to_s.strip.start_with?(prefix) }
    end

    # Assert a command may run. Always rejects a prohibited shape. When `strict:` (agent-proposed
    # commands), also requires an allowed prefix. Raises ProhibitedCommand otherwise.
    def assert_allowed!(command, strict: false)
      reason = prohibited_reason(command)
      raise ProhibitedCommand, "prohibited command (#{reason}): #{command}" if reason
      if strict && !allowed_prefix?(command)
        raise ProhibitedCommand, "command not on the controller allowlist: #{command}"
      end

      command
    end
  end
end
