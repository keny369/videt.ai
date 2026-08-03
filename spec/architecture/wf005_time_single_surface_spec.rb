# frozen_string_literal: true

require "rails_helper"
require "open3"
require "ripper"

# ADR-117's one authorised WF-005 fitness check. PostgreSQL instants in this workflow have one
# decoder, `Platform::PgInstant`; this check discovers the tracked recursive corpus and parses Ruby
# syntax so comments and string literals cannot manufacture either a violation or conformity.
RSpec.describe "WF-005 PostgreSQL time single-surface fitness", type: :model do
  # Methods, not example-group constants: constants assigned in an RSpec block land on Object and can
  # collide with another spec according to load order (FU-42).
  def parser_methods = %w[parse iso8601 strptime]
  def type_tests = %w[is_a? kind_of? instance_of?]
  def utc_protocol = %w[getutc to_time]

  def tracked_ruby_files
    stdout, status = Open3.capture2("git", "ls-files", "--", "app/workflows/wf005")
    raise "git ls-files failed" unless status.success?

    stdout.lines.map(&:strip).select { |path| path.end_with?(".rb") }.sort
  end

  def each_node(node, &block)
    return unless node.is_a?(Array)

    yield node
    node.each { |child| each_node(child, &block) if child.is_a?(Array) }
  end

  def token(node, kind = nil)
    return unless node.is_a?(Array) && node.first.to_s.start_with?("@")
    return unless kind.nil? || node.first == kind

    node[1]
  end

  def constant_name(node)
    return unless node.is_a?(Array)

    case node.first
    when :var_ref, :const_ref, :top_const_ref
      token(node[1], :@const)
    when :const_path_ref, :const_path_field
      left = constant_name(node[1])
      right = token(node[2], :@const)
      [left, right].compact.join("::") unless right.nil?
    end
  end

  def contains_constant?(node, *names)
    found = false
    each_node(node) { |part| found ||= names.include?(constant_name(part)) }
    found
  end

  def contains_token?(node, kind, *names)
    found = false
    each_node(node) { |part| found ||= names.include?(token(part, kind)) }
    found
  end

  def line_of(node)
    found = nil
    each_node(node) do |part|
      location = part[2] if part.first.to_s.start_with?("@")
      found ||= location[0] if location.is_a?(Array)
    end
    found || 1
  end

  # Returns syntax-derived findings. This is deliberately a callable detector so the examples below
  # prove it both rejects local implementations and accepts canonical calls before it scans production.
  def violations(source, file: "synthetic.rb")
    tree = Ripper.sexp(source)
    return ["#{file}:1 is not parseable Ruby"] if tree.nil?

    findings = []
    each_node(tree) do |node|
      case node.first
      when :call
        receiver, method = node[1], node[3]
        if %w[Time DateTime].include?(constant_name(receiver)) && parser_methods.include?(token(method, :@ident))
          findings << "#{file}:#{line_of(method)} locally parses a timestamp"
        end
      when :method_add_arg
        call, arguments = node[1], node[2]
        next unless call.is_a?(Array) && call.first == :call

        method = token(call[3], :@ident)
        if type_tests.include?(method) && contains_constant?(arguments, "Time", "DateTime")
          findings << "#{file}:#{line_of(call[3])} locally dispatches on timestamp type"
        elsif method == "respond_to?" && contains_token?(arguments, :@ident, *utc_protocol)
          findings << "#{file}:#{line_of(call[3])} locally dispatches on timestamp protocol"
        end
      when :when, :in
        if contains_constant?(node[1], "Time", "DateTime")
          findings << "#{file}:#{line_of(node[1])} locally dispatches on timestamp type"
        end
      when :binary
        left, _operator, right = node[1], node[2], node[3]
        left_class = left.is_a?(Array) && left.first == :call && token(left[3], :@ident) == "class"
        right_class = right.is_a?(Array) && right.first == :call && token(right[3], :@ident) == "class"
        if (left_class && contains_constant?(right, "Time", "DateTime")) ||
           (right_class && contains_constant?(left, "Time", "DateTime"))
          findings << "#{file}:#{line_of(node)} locally dispatches on timestamp class"
        end
      end
    end
    findings.uniq
  end

  def canonical_usage?(source)
    tree = Ripper.sexp(source)
    return false if tree.nil?

    found = false
    each_node(tree) do |node|
      next unless node.first == :call

      found ||= constant_name(node[1]) == "Platform::PgInstant" &&
                %w[utc elapsed_minutes].include?(token(node[3], :@ident))
    end
    found
  end

  it "proves the syntax detector against conforming, commented and violating programs" do
    conforming = <<~RUBY
      # Time.parse(row["deadline_at"])
      warning = "value.respond_to?(:getutc)"
      deadline = Platform::PgInstant.utc(row["deadline_at"])
      now.utc < deadline
    RUBY
    expect(violations(conforming)).to be_empty

    violating = {
      "parser" => "Time.parse(value.to_s)",
      "type test" => "value.is_a?(Time) ? value.getutc : value",
      "protocol test" => "value.respond_to?(:getutc) ? value.getutc : value",
      "case dispatch" => "case value; when Time; value.getutc; else; value; end",
      "class dispatch" => "value.class == Time ? value.getutc : value"
    }
    violating.each do |label, program|
      expect(violations(program, file: "#{label}.rb")).not_to be_empty, "detector missed #{label}"
    end
  end

  it "finds no second timestamp decoder in the recursive tracked WF-005 corpus" do
    findings = tracked_ruby_files.flat_map do |relative|
      violations(Rails.root.join(relative).read, file: relative)
    end

    expect(findings).to be_empty, <<~MESSAGE
      WF-005 PostgreSQL timestamps must be decoded only through Platform::PgInstant.
      Local parsing or type dispatch creates a second precision-sensitive implementation:
      #{findings.join("\n")}
    MESSAGE
  end

  it "proves the discovered corpus is non-empty and contains canonical syntax" do
    expect(tracked_ruby_files.length).to be > 20
    expect(tracked_ruby_files).to all(start_with("app/workflows/wf005/").and(end_with(".rb")))
    canonical = tracked_ruby_files.select { |path| canonical_usage?(Rails.root.join(path).read) }
    expect(canonical).not_to be_empty
  end

  it "decodes typed, textual and nullable instants exactly, in UTC, without mutation" do
    typed = Time.new(2026, 8, 3, 12, 34, 56 + Rational(123_456, 1_000_000), "+10:00")
    before = [typed.object_id, typed.utc_offset, typed.usec, typed.strftime("%Y-%m-%dT%H:%M:%S.%6N%:z")]
    decoded = Platform::PgInstant.utc(typed)

    expect(decoded).to eq(Time.utc(2026, 8, 3, 2, 34, 56, 123_456))
    expect(decoded.utc?).to be(true)
    expect([typed.object_id, typed.utc_offset, typed.usec, typed.strftime("%Y-%m-%dT%H:%M:%S.%6N%:z")])
      .to eq(before)
    expect(decoded).not_to equal(typed)
    expect(Platform::PgInstant.utc("2026-08-03T12:34:56.654321+10:00"))
      .to eq(Time.utc(2026, 8, 3, 2, 34, 56, 654_321))
    expect(Platform::PgInstant.utc(nil)).to be_nil
  end

  it "keeps 59.99 elapsed minutes below 60 and admits the exact 60-minute boundary" do
    started = Time.utc(2026, 8, 3, 2, 0, 0, 123_456)
    expect(Platform::PgInstant.elapsed_minutes(started, started + Rational(3_599_400_000, 1_000_000)))
      .to eq(59)
    expect(Platform::PgInstant.elapsed_minutes(started.iso8601(6), (started + 3_600).iso8601(6)))
      .to eq(60)
  end
end
