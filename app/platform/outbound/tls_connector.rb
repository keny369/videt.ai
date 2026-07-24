# frozen_string_literal: true

require "socket"
require "openssl"
require "ipaddr"

module Platform
  module Outbound
    # The production socket/TLS layer behind GuardedHttpClient — the ONE place raw
    # sockets and OpenSSL are used in the whole application (FOUNDATION-001 property 10;
    # enforced by the outbound architecture fitness spec). It is the only component that
    # can actually open an egress connection, and it enforces the three transport-level
    # safety properties before a single response byte is read:
    #
    #  - it connects to EXACTLY the pinned address (never re-resolving the host);
    #  - it verifies the connected transport peer equals the pinned address
    #    (FOUNDATION-001 property 3 — the explicit DNS-rebinding backstop);
    #  - it presents the canonical host as TLS SNI and validates the certificate chain
    #    and hostname (property 8), sending the canonical host as the HTTP Host header is
    #    the client's job.
    #
    # It translates every socket/OpenSSL failure into the client's neutral typed error
    # so a raw error never escapes the adapter. The SSL context is injectable so the
    # integration test can trust a local certificate authority; production builds the
    # default context that trusts the system roots.
    class TlsConnector
      MIN_CONNECT_TIMEOUT_S = 0.05

      def initialize(ssl_context: nil)
        @ssl_context = ssl_context
      end

      def open(pinned:, host:, port:, deadline:)
        socket = connect(pinned, port, deadline)
        verify_peer!(socket, pinned)
        ssl = establish_tls(socket, host)
        Connection.new(ssl)
      end

      # Pure peer-equality decision, extracted so it is unit-testable without a socket.
      # IPv4-mapped IPv6 is normalised so a mapped peer matches its IPv4 pin.
      def self.peer_matches?(remote_ip, pinned)
        normalize(IPAddr.new(remote_ip.to_s)) == normalize(pinned)
      rescue IPAddr::Error
        false
      end

      def self.normalize(ip)
        ip.ipv6? && (ip.ipv4_mapped? rescue false) ? ip.native : ip
      end

      private

      def connect(pinned, port, deadline)
        Socket.tcp(pinned.to_s, port, connect_timeout: remaining(deadline))
      rescue Errno::ETIMEDOUT, IO::TimeoutError
        raise GuardedHttpClient::TimeoutError, "connect timed out"
      rescue SystemCallError, SocketError => e
        raise GuardedHttpClient::ConnectionError, e.class.name
      end

      def verify_peer!(socket, pinned)
        remote = socket.remote_address.ip_address
        return if self.class.peer_matches?(remote, pinned)

        socket.close
        raise GuardedHttpClient::PeerMismatchError, "transport peer is not the pinned address"
      end

      def establish_tls(socket, host)
        ssl = OpenSSL::SSL::SSLSocket.new(socket, ssl_context)
        ssl.hostname = host        # SNI = canonical host
        ssl.sync_close = true
        ssl.connect                # handshake + chain verification (VERIFY_PEER)
        ssl.post_connection_check(host) # hostname verification against the certificate
        ssl
      rescue OpenSSL::SSL::SSLError, OpenSSL::X509::CertificateError => e
        ssl&.close
        socket.close unless ssl&.sync_close
        raise GuardedHttpClient::TlsError, e.class.name
      rescue SystemCallError => e
        ssl&.close
        socket.close unless ssl&.sync_close
        raise GuardedHttpClient::ConnectionError, e.class.name
      end

      def ssl_context = @ssl_context ||= self.class.default_context

      def self.default_context
        store = OpenSSL::X509::Store.new
        store.set_default_paths
        context = OpenSSL::SSL::SSLContext.new
        context.cert_store = store
        context.min_version = OpenSSL::SSL::TLS1_2_VERSION
        context.verify_mode = OpenSSL::SSL::VERIFY_PEER
        context.verify_hostname = true
        context.freeze
      end

      def remaining(deadline)
        [deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC), MIN_CONNECT_TIMEOUT_S].max
      end

      # The connected, TLS-verified duplex the reader drives. `read` enforces the
      # request deadline with non-blocking reads + IO.select, returning nil at EOF and
      # raising the client's neutral TimeoutError/ConnectionError; the reader turns that
      # into line/exact-byte reads. `write` sends the (tiny) request.
      class Connection
        def initialize(ssl)
          @ssl = ssl
          @io = ssl.to_io
        end

        def write(bytes)
          @ssl.write(bytes)
        rescue OpenSSL::SSL::SSLError, SystemCallError => e
          raise GuardedHttpClient::ConnectionError, e.class.name
        end

        def read(max_bytes, deadline)
          @ssl.read_nonblock(max_bytes)
        rescue IO::WaitReadable
          wait(@io, :read, deadline)
          retry
        rescue IO::WaitWritable
          wait(@io, :write, deadline)
          retry
        rescue EOFError
          nil
        rescue OpenSSL::SSL::SSLError, SystemCallError => e
          raise GuardedHttpClient::ConnectionError, e.class.name
        end

        def close
          @ssl.close
        rescue StandardError
          nil
        end

        private

        def wait(io, direction, deadline)
          timeout = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          raise GuardedHttpClient::TimeoutError, "response deadline exceeded" if timeout <= 0

          ready =
            if direction == :read
              IO.select([io], nil, nil, timeout)
            else
              IO.select(nil, [io], nil, timeout)
            end
          raise GuardedHttpClient::TimeoutError, "response deadline exceeded" if ready.nil?
        end
      end
    end
  end
end
