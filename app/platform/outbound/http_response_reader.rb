# frozen_string_literal: true

module Platform
  module Outbound
    # Reads and parses ONE HTTP/1.x response off an already-connected, TLS-verified
    # Connection (FOUNDATION-001 property 6). It owns exactly two safety properties the
    # rest of the transport depends on:
    #
    #  1. The byte cap is enforced on DECODED entity-body bytes. The reader accumulates
    #     at most `read_limit` (= byte_cap + 1) bytes and stops; reaching that count is
    #     `truncated` = oversize. Chunk framing bytes are not entity body, and no
    #     content-decoding is performed (the client asks for `identity`), so "compressed
    #     transfer size" can never be what is measured — the cap is the body the caller
    #     would consume. `Content-Length` is used only to know when a body ends, never
    #     trusted as the byte count (SCORE_EVIDENCE_MODEL.md :144-145).
    #
    #  2. Request-smuggling shapes are refused, not guessed: a `Transfer-Encoding` and a
    #     `Content-Length` together, or two disagreeing `Content-Length` values, are a
    #     ProtocolError rather than a silently-chosen framing.
    #
    # It never interprets the body; it returns raw bytes for the caller's own digest.
    class HttpResponseReader
      CRLF = "\r\n"
      STATUS_LINE_MAX = 8 * 1024
      HEADER_SECTION_MAX = 64 * 1024
      CHUNK_LINE_MAX = 1 * 1024
      PULL_SIZE = 16 * 1024

      # The raw response surfaced to the client. `headers` maps lowercased name to its
      # first value; `body` is ASCII-8BIT, at most read_limit bytes.
      RawResponse = Data.define(:status, :headers, :body, :byte_count, :truncated)

      def self.read(connection, deadline:, read_limit:)
        new(connection, deadline, read_limit).read
      end

      def initialize(connection, deadline, read_limit)
        @reader = ByteReader.new(connection, deadline)
        @read_limit = read_limit
      end

      def read
        status = read_status
        headers = read_headers
        body, byte_count, truncated = read_body(headers)
        RawResponse.new(status:, headers:, body:, byte_count:, truncated:)
      end

      private

      def read_status
        line = @reader.read_line(STATUS_LINE_MAX)
        # HTTP-version SP status-code SP [reason]
        match = line.match(%r{\AHTTP/\d\.\d (\d{3})(?: .*)?\z})
        raise GuardedHttpClient::ProtocolError, "malformed status line" unless match

        match[1].to_i
      end

      # Parse the header block into first-value-wins, enforcing the anti-smuggling rules.
      def read_headers
        first = {}
        content_lengths = []
        has_transfer_encoding = false
        consumed = 0

        loop do
          line = @reader.read_line(HEADER_SECTION_MAX)
          break if line.empty?

          consumed += line.bytesize + 2
          raise GuardedHttpClient::ProtocolError, "header section too large" if consumed > HEADER_SECTION_MAX

          name, value = split_header(line)
          key = name.downcase
          first[key] ||= value
          content_lengths << value.strip if key == "content-length"
          has_transfer_encoding = true if key == "transfer-encoding"
        end

        reject_smuggling(content_lengths, has_transfer_encoding)
        first
      end

      def split_header(line)
        idx = line.index(":")
        raise GuardedHttpClient::ProtocolError, "malformed header line" if idx.nil? || idx.zero?

        [line.byteslice(0, idx).strip, line.byteslice(idx + 1..).to_s.strip]
      end

      def reject_smuggling(content_lengths, has_transfer_encoding)
        if has_transfer_encoding && content_lengths.any?
          raise GuardedHttpClient::ProtocolError, "Transfer-Encoding with Content-Length"
        end
        if content_lengths.uniq.length > 1
          raise GuardedHttpClient::ProtocolError, "conflicting Content-Length"
        end
      end

      def read_body(headers)
        body =
          if chunked?(headers["transfer-encoding"])
            read_chunked
          elsif (cl = headers["content-length"])
            read_fixed(content_length(cl))
          else
            read_until_eof
          end

        [body, body.bytesize, body.bytesize == @read_limit]
      end

      def chunked?(value)
        return false unless value

        value.split(",").map { |t| t.strip.downcase }.include?("chunked")
      end

      def content_length(value)
        Integer(value.strip, 10)
      rescue ArgumentError, TypeError
        raise GuardedHttpClient::ProtocolError, "invalid Content-Length"
      end

      # Read up to min(length, read_limit) entity-body bytes.
      def read_fixed(length)
        raise GuardedHttpClient::ProtocolError, "negative Content-Length" if length.negative?

        pull_into((+"").b, [length, @read_limit].min)
      end

      # Read entity-body bytes until EOF, capped at read_limit.
      def read_until_eof
        pull_into((+"").b, @read_limit)
      end

      # Accumulate bytes into `body` up to `limit`, from the buffered reader.
      def pull_into(body, limit)
        while body.bytesize < limit
          chunk = @reader.read_bytes(limit - body.bytesize)
          break if chunk.empty? # EOF

          body << chunk
        end
        body
      end

      # Decode chunked transfer-coding, capping the DECODED bytes at read_limit. Chunk
      # sizes and framing bytes are not counted; only chunk data is entity body.
      def read_chunked
        body = (+"").b
        loop do
          size = parse_chunk_size(@reader.read_line(CHUNK_LINE_MAX))
          break if size.zero?

          consume_chunk_data(body, size)
          break if body.bytesize >= @read_limit # cap reached mid-stream: stop, leave the rest unread

          expect_crlf
        end
        body
      end

      def parse_chunk_size(line)
        hex = line.split(";", 2).first.to_s.strip
        raise GuardedHttpClient::ProtocolError, "empty chunk size" if hex.empty?

        Integer(hex, 16)
      rescue ArgumentError
        raise GuardedHttpClient::ProtocolError, "invalid chunk size"
      end

      # Read `size` bytes of chunk data into body, but never past read_limit. If the cap
      # is hit mid-chunk the surplus is left unread (the connection is closed after).
      def consume_chunk_data(body, size)
        remaining = size
        while remaining.positive? && body.bytesize < @read_limit
          want = [remaining, @read_limit - body.bytesize].min
          chunk = @reader.read_bytes(want)
          raise GuardedHttpClient::ProtocolError, "truncated chunk" if chunk.empty?

          body << chunk
          remaining -= chunk.bytesize
        end
      end

      def expect_crlf
        trailer = @reader.read_bytes(2)
        raise GuardedHttpClient::ProtocolError, "missing chunk CRLF" unless trailer == CRLF
      end

      # A small buffered reader over the Connection. `read` returns nil at EOF and raises
      # GuardedHttpClient::TimeoutError once the deadline passes; the buffering above it
      # turns that into line/exact-byte reads without over-reading the socket.
      class ByteReader
        def initialize(connection, deadline, pull_size: PULL_SIZE)
          @connection = connection
          @deadline = deadline
          @pull_size = pull_size
          @buffer = (+"").b
          @eof = false
        end

        # Read one CRLF-terminated line (CRLF stripped). Refuses a line longer than max.
        def read_line(max_bytes)
          loop do
            if (idx = @buffer.index(CRLF))
              line = @buffer.slice!(0, idx + 2)
              return line.byteslice(0, line.bytesize - 2)
            end
            raise GuardedHttpClient::ProtocolError, "line exceeds #{max_bytes} bytes" if @buffer.bytesize > max_bytes
            raise GuardedHttpClient::ProtocolError, "unexpected EOF before end of line" if @eof

            fill
          end
        end

        # Return up to n bytes; "" only at EOF.
        def read_bytes(count)
          fill while @buffer.bytesize < count && !@eof
          @buffer.slice!(0, [count, @buffer.bytesize].min)
        end

        private

        def fill
          chunk = @connection.read(@pull_size, @deadline)
          if chunk.nil? || chunk.empty?
            @eof = true
          else
            @buffer << chunk.b
          end
        end
      end
    end
  end
end
