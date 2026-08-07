# frozen_string_literal: true

require "fileutils"

module Platform
  # A DEVELOPMENT-ONLY stand-in for the guarded egress surface, so WF-003 ownership
  # verification can be exercised on a laptop.
  #
  # WHY THIS EXISTS. A real ownership check requires control of a real domain: the
  # observer resolves `_f1-verify.<host>` or fetches `https://<host>/.well-known/
  # f1-verification.txt` over the internet. That is exactly right in production and
  # exactly unusable in development, where the developer's Source host does not exist.
  # Without something here the product's only path from `proposed` to `verified` is
  # unreachable locally, which is what kept the whole chain — verify, activate, crawl —
  # from being walkable at all.
  #
  # WHAT IT IS NOT. It is not a verification bypass. It replaces ONE thing: the network
  # read. The challenge token is still generated, encrypted and revealed by F-02; the
  # ratified DNS/HTTP predicate in `Workflows::Wf003::VerificationObservation` still
  # decides the match over raw bytes; a wrong value still produces `dns_value_mismatch`
  # or `http_content_mismatch`; the Evidence, the events and the atomic success commit
  # are the production ones. A developer who writes the wrong value into the fixture
  # file does not verify. The observation is real; only the transport is local.
  #
  # HOW IT CANNOT REACH PRODUCTION. `enabled?` is false unless `Rails.env.development?`,
  # and the environment check is first, so no environment variable can turn it on
  # anywhere else. `surface` is the only way a caller obtains an observer, and it
  # returns the real `Platform::Outbound` whenever the flag is not both development and
  # explicitly set. Constructing the fixture reader raises outside development, so even
  # a direct reference cannot instantiate it in a deployed process.
  #
  # It opens no socket and holds no transport primitive: it reads one local file. The
  # F-01 single-surface fitness check therefore still holds — this is not a second
  # egress path, it is the absence of one.
  module DevelopmentVerificationOutbound
    ENV_FLAG = "F1_DEV_VERIFICATION"
    ENV_DIR = "F1_DEV_VERIFICATION_DIR"
    DEFAULT_DIR = "tmp/dev_verification"

    # The two locations the observation engine constructs. Parsed back to a canonical
    # host so one fixture file per host serves both methods.
    DNS_PREFIX = "_f1-verify."
    WELL_KNOWN_PATH = "/.well-known/f1-verification.txt"
    HTTPS_PREFIX = "https://"

    # A host is only ever taken from a Source that WF-004 already canonicalized, so this
    # is a defence against a path-traversal filename, not a validation of the host.
    SAFE_HOST = /\A[a-z0-9]([a-z0-9\-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9\-]{0,61}[a-z0-9])?)+\z/

    class NotAvailable < StandardError; end

    module_function

    # Development AND explicitly asked for. The environment test is first and
    # unconditional: `F1_DEV_VERIFICATION=1` in a production process changes nothing.
    def enabled?
      Rails.env.development? && ENV[ENV_FLAG] == "1"
    end

    # The observer a WF-003 caller passes as `outbound:`. Every environment except an
    # opted-in development one gets the real guarded transport, so the default is the
    # production path and the local path is the exception a developer must ask for.
    def surface
      enabled? ? Reader.new(directory) : Platform::Outbound
    end

    def directory
      Rails.root.join(ENV.fetch(ENV_DIR, DEFAULT_DIR))
    end

    def record_path(canonical_host)
      raise NotAvailable, "canonical host is not a plain hostname" unless canonical_host.to_s.match?(SAFE_HOST)

      directory.join("#{canonical_host}.txt")
    end

    # Write the value a developer would otherwise publish in DNS or at the well-known
    # URL. Refuses outside an enabled development process, so this is not a path a
    # deployed build can call.
    def place(canonical_host:, value:)
      raise NotAvailable, "development verification records are not available here" unless enabled?

      path = record_path(canonical_host)
      FileUtils.mkdir_p(path.dirname)
      File.write(path, "#{value}\n")
      path
    end

    def placed?(canonical_host)
      enabled? && File.exist?(record_path(canonical_host))
    end

    # ---- duck-typed results ---------------------------------------------------
    #
    # Shaped to what the observation engine reads, never to an internal transport
    # class: the engine consumes `refused?`/`records` and `response?`/`rejected?`/
    # `kind`/`status`/`body`/`byte_count`/`truncated`, and nothing else.

    TxtAnswer = Data.define(:records) do
      def refused? = false
      def reason = nil
    end

    TxtRefusal = Data.define(:reason) do
      def refused? = true
      def records = []
    end

    HttpOutcome = Data.define(:status, :body, :byte_count, :truncated) do
      def response? = true
      def rejected? = false
      def kind = :response
      def reason = nil
    end

    # Reads the local fixture file for a canonical host and answers as the two guarded
    # calls would. An absent file is a definitive negative — NXDOMAIN for DNS, 404 for
    # HTTP — so the "I have not published it yet" case behaves exactly as it does live.
    class Reader
      # An explicit allowlist rather than `unless production?`: a future environment
      # name (staging, review, demo) must fail closed without anyone remembering to
      # add it here. The test environment may construct one to prove its behaviour,
      # but `enabled?` stays development-only, so no test-environment request path
      # can select it by accident.
      def initialize(directory)
        unless Rails.env.development? || Rails.env.test?
          raise NotAvailable, "development verification transport cannot exist here"
        end

        @directory = directory
      end

      def fetch_dns_txt(location, timeout_s:) # rubocop:disable Lint/UnusedMethodArgument
        value = read(location.to_s.delete_prefix(DevelopmentVerificationOutbound::DNS_PREFIX))
        return TxtRefusal.new(reason: :absent) if value.nil?

        # One record of one character-string, which is how a published TXT record for a
        # single value arrives from a resolver.
        TxtAnswer.new(records: [[value]])
      end

      def fetch(url, timeout_s:, byte_cap:, total_timeout_s: nil, max_redirects: 0, **) # rubocop:disable Lint/UnusedMethodArgument
        host = host_from(url.to_s)
        value = host && read(host)
        return HttpOutcome.new(status: 404, body: "".b, byte_count: 0, truncated: false) if value.nil?

        body = "#{value}\n".b
        HttpOutcome.new(status: 200, body: body.byteslice(0, byte_cap), byte_count: body.bytesize,
                        truncated: body.bytesize > byte_cap)
      end

      private

      def host_from(url)
        return nil unless url.start_with?(DevelopmentVerificationOutbound::HTTPS_PREFIX) &&
                          url.end_with?(DevelopmentVerificationOutbound::WELL_KNOWN_PATH)

        url.delete_prefix(DevelopmentVerificationOutbound::HTTPS_PREFIX)
           .delete_suffix(DevelopmentVerificationOutbound::WELL_KNOWN_PATH)
      end

      # The trailing newline a developer's editor adds is not part of the value: the
      # HTTP predicate already tolerates exactly one trailing line feed, and a DNS
      # character-string never carries one.
      def read(host)
        return nil unless host.to_s.match?(DevelopmentVerificationOutbound::SAFE_HOST)

        path = @directory.join("#{host}.txt")
        return nil unless File.exist?(path)

        File.read(path).chomp
      end
    end
  end
end
