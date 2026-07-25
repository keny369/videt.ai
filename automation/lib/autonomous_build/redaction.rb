# frozen_string_literal: true

module AutonomousBuild
  # Secret redaction (mandate §8.4, §13; AGENT_OUTPUT_SCHEMAS "No schema may contain secrets").
  # Secrets must never reach prompts, logs, run records or captured command output. Redaction is
  # applied to everything the controller persists or sends. It over-redacts by design: a false
  # redaction is harmless; a leaked credential is not.
  module Redaction
    module_function

    REPLACEMENT = "[REDACTED]"

    # Whole-token secret shapes -> replace the entire match.
    TOKEN_PATTERNS = [
      /\bsk-ant-[A-Za-z0-9_-]{16,}\b/,                 # Anthropic API keys
      /\bsk-[A-Za-z0-9_-]{20,}\b/,                     # OpenAI-style keys
      /\bgh[pousr]_[A-Za-z0-9]{20,}\b/,                # GitHub tokens
      /\bAKIA[0-9A-Z]{16}\b/,                          # AWS access key id
      /\bxox[baprs]-[A-Za-z0-9-]{10,}\b/,              # Slack tokens
      /\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b/ # JWTs
    ].freeze

    # key=value / key: value with a sensitive key -> keep the key, redact the value.
    KEY_VALUE = /\b(password|passwd|secret|token|api[_-]?key|access[_-]?key|authorization|bearer|private[_-]?key)\b(\s*[:=]\s*)("?)([^\s"']+)\3/i

    # credentials embedded in a URL (redis://user:pass@host, https://user:pass@host) -> redact user:pass.
    URL_CREDENTIALS = %r{(\b[a-z][a-z0-9+.-]*://)([^:@/\s]+):([^@/\s]+)@}i

    # Redact known secret shapes and any explicitly-supplied secret VALUES (e.g. the literal value of
    # ANTHROPIC_API_KEY read from the environment) so an exact credential can never slip through.
    def redact(text, extra_secrets: [])
      return text unless text.is_a?(String)

      result = text.dup
      Array(extra_secrets).compact.map(&:to_s).reject { |s| s.length < 6 }.each do |secret|
        result = result.gsub(secret, REPLACEMENT)
      end
      TOKEN_PATTERNS.each { |re| result = result.gsub(re, REPLACEMENT) }
      result = result.gsub(KEY_VALUE) { "#{Regexp.last_match(1)}#{Regexp.last_match(2)}#{REPLACEMENT}" }
      result.gsub(URL_CREDENTIALS) { "#{Regexp.last_match(1)}#{REPLACEMENT}:#{REPLACEMENT}@" }
    end

    # Deep-redact a structure destined for a run record / prompt (strings inside hashes/arrays).
    def redact_deep(value, extra_secrets: [])
      case value
      when String then redact(value, extra_secrets:)
      when Array then value.map { |v| redact_deep(v, extra_secrets:) }
      when Hash then value.to_h { |k, v| [k, redact_deep(v, extra_secrets:)] }
      else value
      end
    end

    # The secret VALUES the controller knows about from the environment, to redact literally.
    def environment_secrets(env: ENV)
      env.select { |k, _| k.match?(/(KEY|TOKEN|SECRET|PASSWORD|CREDENTIAL)/i) }.values.compact.reject(&:empty?)
    end
  end
end
