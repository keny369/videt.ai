# frozen_string_literal: true

require "rails_helper"
require "open3"
require "ripper"

# ADR-117's one authorised WF-005 fitness check. PostgreSQL instants in this workflow have one
# decoder, `Platform::PgInstant`; this check discovers the tracked recursive corpus and parses Ruby
# syntax so comments and string literals cannot manufacture either a violation or conformity.
#
# IT IS AN ALLOWLIST NOW, NOT A LIST OF KNOWN-BAD SHAPES (round 6, R6-7).
#
# THE DEFECT THIS REPLACES. The first version enumerated four AST forms — `Time.parse`,
# `x.is_a?(Time)`, `x.respond_to?(:getutc)` with parentheses, `x.class == Time` — and proved itself
# against those same four. Round 6 called the committed `violations` helper directly and got an empty
# finding set for four ordinary spellings of the very thing it exists to forbid:
#
#     Time.zone.parse(value.to_s)     # the receiver is a call, so `constant_name` returned nil
#     Time.rfc3339(value.to_s)        # `rfc3339` was not in the method list
#     value.respond_to? :getutc       # no parentheses, so it is `command_call`, not `method_add_arg`
#     Time === value ? value.getutc : value   # neither operand is a `.class` call
#
# Adding four more shapes would have reproduced the defect one round later, because the flaw was never
# the coverage of the list — it was that a list of forbidden spellings can always be respelled.
#
# WHAT IT ASSERTS INSTEAD, and why this is enforceable rather than aspirational: THE TRACKED WF-005
# CORPUS NAMES `Time` AND `DateTime` NOWHERE AT ALL. Not once, in any of the tracked files. Every
# instant this workflow reads out of PostgreSQL goes through `Platform::PgInstant`, and every instant
# it writes is one the application already holds. So the rule is not "these four shapes are
# forbidden", it is "this constant may not be named here" — which no respelling can evade, because
# every parser, every type test, every `case/when`, every `===` and every `.class ==` comparison has
# to name it to do its work.
#
# THE SECOND RULE IS THE PROTOCOL'S. `respond_to?(:getutc)` needs no constant, so a symbol literal
# naming the UTC protocol is banned alongside. The two `.getutc` method CALLS in the corpus are
# untouched and correct: they format an instant the application already holds, which is a different
# act from deciding how to decode one.
RSpec.describe "WF-005 PostgreSQL time single-surface fitness", type: :model do
  # Methods, not example-group constants: constants assigned in an RSpec block land on Object and can
  # collide with another spec according to load order (FU-42).
  #
  # NAMING EITHER OF THESE IN WF-005 IS THE VIOLATION. There is no list of methods, because the rule
  # is about the constant rather than about what is done with it.
  def banned_constants = %w[Time DateTime]
  # The UTC protocol, AS A SYMBOL LITERAL — which is dispatch — never as a method call, which is use.
  def banned_symbols = %w[getutc to_time]

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

  # The UTC protocol NAMED AS DATA, in whichever spelling produced it: `:getutc`, `%i[getutc]`,
  # `"getutc"`. All three are dispatch — `respond_to?` and `send` accept a String as readily as a
  # Symbol — and all three reach the same decision a type test would.
  #
  # A METHOD CALL IS NOT REACHED BY ANY OF THEM. `time.getutc` is an `@ident` in call position, which
  # is use rather than dispatch, and the corpus contains two legitimate ones.
  #
  # THE STRING LIMB MATCHES THE WHOLE CONTENT, WHICH IS WHY IT IS NOT A PROSE RULE. A comment is not in
  # the tree at all, and a sentence that mentions the protocol — `"value.respond_to?(:getutc)"` — is
  # one `@tstring_content` token holding the whole sentence and does not equal the protocol name. Only
  # a literal whose entire content IS the method name matches, and that literal has exactly one use.
  def protocol_names(node)
    case node.first
    when :symbol then [token(node[1], :@ident), token(node[1], :@const), token(node[1], :@kw)].compact
    else [token(node, :@tstring_content)].compact
    end
  end

  # Returns syntax-derived findings. Deliberately a callable detector so the examples below prove it
  # against independently constructed programs before it scans production.
  #
  # TWO RULES, BOTH STRUCTURAL. Neither enumerates a spelling, so neither can be respelled around:
  #
  #   1. the tracked corpus may not NAME `Time` or `DateTime`, in any syntactic position;
  #   2. it may not name the UTC protocol AS A SYMBOL, which is the one way to dispatch on a
  #      timestamp without naming its class.
  def violations(source, file: "synthetic.rb")
    tree = Ripper.sexp(source)
    return ["#{file}:1 is not parseable Ruby"] if tree.nil?

    findings = []
    each_node(tree) do |node|
      # RULE 1. Any `@const` token, wherever it sits: `Time.parse`, `::Time`, `Time.zone.parse`,
      # `when Time`, `Time === x`, `x.class == Time`, `x.is_a?(Time)`, `Time::at` — all of them have
      # to produce this token to mean anything.
      constant = token(node, :@const)
      if banned_constants.include?(constant)
        findings << "#{file}:#{node[2].is_a?(Array) ? node[2][0] : 1} names #{constant}; " \
                    "PostgreSQL instants are decoded only by Platform::PgInstant"
      end

      # RULE 2. `respond_to? :getutc`, with or without parentheses, and every other symbol-shaped
      # dispatch on the UTC protocol.
      protocol_names(node).each do |name|
        next unless banned_symbols.include?(name)

        findings << "#{file}:#{line_of(node)} dispatches on the :#{name} protocol; " \
                    "PostgreSQL instants are decoded only by Platform::PgInstant"
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
      elapsed = Platform::PgInstant.elapsed_minutes(row["started_at"], now)
      stamped = now.getutc.iso8601(6)
      now.utc < deadline
    RUBY
    expect(violations(conforming)).to be_empty

    # THE FOUR ROUND-6 ESCAPES, VERBATIM FROM THE REVIEW. Each returned an empty finding set against
    # the committed detector, and each is the first thing this rewrite must catch.
    escaped = {
      "zone parser" => "Time.zone.parse(value.to_s)",
      "rfc3339" => "Time.rfc3339(value.to_s)",
      "parenless protocol" => "value.respond_to? :getutc",
      "case equality" => "Time === value ? value.getutc : value"
    }
    escaped.each do |label, program|
      expect(violations(program, file: "#{label}.rb")).not_to be_empty,
                                                             "R6-7 escape still undetected: #{label}"
    end

    # AND FORMS THE DETECTOR HAS NEVER BEEN TOLD ABOUT, constructed from the rule rather than copied
    # from its implementation. None of these appears in `violations`.
    independent = {
      "top-level scope" => "::Time.parse(value)",
      "scope resolution call" => "Time::at(value)",
      "datetime parser" => "DateTime.iso8601(value)",
      "safe navigation" => "value&.is_a?(Time)",
      "pattern match" => "case value; in Time then value; end",
      "assignment" => "klass = Time; klass.parse(value)",
      "rescue clause" => "begin; f; rescue Time::Error; nil; end",
      "array membership" => "[Time, DateTime].any? { |k| value.is_a?(k) }",
      "method reference" => "value.method(:to_time).call",
      "symbol array" => "%i[getutc to_time].any? { |m| value.respond_to?(m) }",
      "send dispatch" => "value.send(:getutc)",
      "keyword argument" => "decode(protocol: :to_time)"
    }
    independent.each do |label, program|
      expect(violations(program, file: "#{label}.rb")).not_to be_empty,
                                                             "detector missed an unlisted form: #{label}"
    end
  end

  it "rejects the banned constants under method names it has never been given" do
    # THE PROPERTY THAT DISTINGUISHES AN ALLOWLIST FROM A LONGER DENYLIST. The old detector carried
    # `%w[parse iso8601 strptime]` and was blind to everything else, which is exactly how `rfc3339`
    # walked through it. These method names are invented for this example and are not mentioned
    # anywhere in the detector, so a rule keyed to a method list cannot pass.
    %w[rfc2822 httpdate xmlschema at now local gm mktime json_create some_future_constructor].each do |method|
      banned_constants.each do |constant|
        program = "#{constant}.#{method}(value)"
        expect(violations(program, file: "#{constant}-#{method}.rb")).not_to be_empty,
                                                                            "detector missed #{program}"
      end
    end
  end

  it "does not fire on the legitimate uses the corpus actually contains" do
    # THE RULE MUST NOT BE A BLANKET BAN ON THE WORD. `.getutc` as a METHOD CALL formats an instant the
    # application already holds — `CrawlLedger#iso` and `CrawlDriver`'s due-instant comparison both do
    # it — and that is a different act from deciding how to DECODE one. Banning it would have forced
    # those two call sites to invent a workaround, which is how a fitness check starts being routed
    # around instead of obeyed.
    permitted = <<~RUBY
      def iso(time) = time&.getutc&.iso8601(6)
      return nil unless due_at && stage_instant(latest) == due_at.getutc
      outcome.respond_to?(:response?) && outcome.response?
      value.is_a?(::Hash)
    RUBY
    expect(violations(permitted)).to be_empty
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
