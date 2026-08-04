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
# naming the UTC protocol is banned alongside, as is a string literal whose whole content is a banned
# constant name — `Object.const_get("Time")` reaches rule 1 through a side door otherwise.
#
# THE THIRD RULE IS THE RECEIVER'S (round 7, A-1). Rules 1 and 2 are about NAMES, and a name can be
# renamed around exactly as a spelling can be respelled: round 7 walked nine forms past them, of
# which `row["deadline_at"].to_time` is the plainest — it names no constant, uses no symbol, and IS
# the connection-dependent decode this module exists to own. What separates it from the NINE
# legitimate `.getutc` calls in this corpus is not the method but the RECEIVER. A decode acts on a
# value pulled out of a `PG::Result` row, which is string-keyed; a format acts on a local or a
# parameter holding an instant the application already produced. So rule 3 bans the whole
# timestamp vocabulary — derived from the runtime, not listed — on a string-keyed subscript, and says
# nothing about the same method names on a local.
RSpec.describe "WF-005 PostgreSQL time single-surface fitness", type: :model do
  # Methods, not example-group constants: constants assigned in an RSpec block land on Object and can
  # collide with another spec according to load order (FU-42).
  #
  # NAMING EITHER OF THESE IN WF-005 IS THE VIOLATION. There is no list of methods, because the rule
  # is about the constant rather than about what is done with it.
  def banned_constants = %w[Time DateTime]
  # The UTC protocol, AS A SYMBOL LITERAL — which is dispatch — never as a method call, which is use.
  def banned_symbols = %w[getutc to_time]

  # RULE 3'S VOCABULARY, DERIVED FROM THE RUNTIME RATHER THAN LISTED (round 7, A-1).
  #
  # Every method name the timestamp classes define that `Object` does not. It is computed from the
  # loaded classes, so it covers the whole conversion and dispatch API of Ruby AND ActiveSupport —
  # `to_time`, `to_datetime`, `in_time_zone`, `parse`, `iso8601`, `rfc3339`, `strftime`, `strptime`,
  # `utc`, `getutc` — and it GROWS BY ITSELF when a Rails upgrade adds one. That is the difference
  # between this and the enumeration it replaces: round 7 walked nine forms past a hand-written list,
  # and the answer to a list that can be out-enumerated is not a longer list.
  #
  # `Integer`'s methods are subtracted as well as `Object`'s, because the generic numeric conversions
  # a row value legitimately receives — `to_i`, `to_f`, `to_r`, the arithmetic and comparison
  # operators — are also defined on `Time`, and banning `row["state_version"].to_i` would say nothing
  # about timestamps. What survives the subtraction is the timestamp-SPECIFIC surface: `to_time`,
  # `to_datetime`, `to_date`, `in_time_zone`, `parse`, `iso8601`, `rfc3339`, `xmlschema`, `httpdate`,
  # `strftime`, `strptime`, `utc`, `getutc`, `getlocal`, `localtime`, `acts_like_time?`.
  #
  # The four added by hand are dispatch verbs rather than timestamp methods, so they are not on the
  # timestamp classes to be derived from: `acts_like?` is Rails' canonical duck-type test and is
  # defined on `Object`, and the three reflective senders reach any of the above indirectly.
  def timestamp_vocabulary
    @timestamp_vocabulary ||= (
      (Time.instance_methods + Time.methods + DateTime.instance_methods + DateTime.methods +
       Date.instance_methods + ActiveSupport::TimeWithZone.instance_methods).uniq -
        Object.instance_methods - Object.methods -
        Integer.instance_methods - Integer.methods
    ).map(&:to_s).to_set + %w[acts_like? respond_to? send public_send method]
  end

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
  # is use rather than dispatch, and the corpus contains NINE legitimate ones — in `crawl_ledger.rb`,
  # `crawl_driver.rb`, `handlers/complete_crawl.rb` (2), `handlers/start_crawl.rb` (3) and
  # `handlers/record_fetch_attempt.rb` (2). Rule 3 is what distinguishes those from a decode, and it
  # does so by receiver rather than by counting them.
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
        # A BANNED CONSTANT REACHED AS DATA is rule 1 through a side door: `Object.const_get("Time")`
        # and `value.class.name == "Time"` name the constant without producing an `@const` token. A
        # string literal whose entire content is `Time` or `DateTime` has no other use here.
        if banned_constants.include?(name)
          findings << "#{file}:#{line_of(node)} names #{name} as a string; " \
                      "PostgreSQL instants are decoded only by Platform::PgInstant"
        end
        next unless banned_symbols.include?(name)

        findings << "#{file}:#{line_of(node)} dispatches on the :#{name} protocol; " \
                    "PostgreSQL instants are decoded only by Platform::PgInstant"
      end

      # RULE 3. A TIMESTAMP METHOD CALLED ON A VALUE READ OUT OF A RESULT ROW (round 7, A-1).
      #
      # THE RECEIVER IS WHAT DISTINGUISHES DECODING FROM FORMATTING, and rules 1 and 2 could not see
      # it. `row["deadline_at"].to_time` names no constant and uses no symbol, so it walked past both —
      # and it IS the decode this module exists to own: on text it parses, on a `Time` it converts.
      # Meanwhile `now.getutc` and `time&.getutc` are formatting an instant the application already
      # holds, which is a different act, and the corpus does nine of them legitimately.
      #
      # The structural difference is that a decode's receiver is rooted in a SUBSCRIPT or a `fetch` —
      # a value pulled out of a `PG::Result` row — while a format's receiver is a local or a parameter.
      # So this bans the whole `timestamp_vocabulary` on a row-rooted receiver and says nothing about
      # the same names on a local. It covers `to_time`, `to_datetime`, `in_time_zone`,
      # `respond_to?(:strftime)`, `acts_like?(:time)`, `send(:strftime)` and every sibling at once,
      # because the rule is about WHERE the value came from rather than what it is called.
      next unless node.first == :call

      method = token(node[3], :@ident)
      next unless method && timestamp_vocabulary.include?(method)
      next unless row_rooted?(node[1])

      findings << "#{file}:#{line_of(node[3])} calls ##{method} on a value read from a result row; " \
                  "PostgreSQL instants are decoded only by Platform::PgInstant"
    end
    findings.uniq
  end

  # Is this receiver a database row value — a subscript, a `fetch`, or a chain rooted in one?
  #
  # A STRING KEY IS WHAT MAKES IT A ROW. `PG::Result` tuples are string-keyed, and every in-memory
  # structure in this workflow is symbol-keyed: `context[:now]`, `link[:due_at]`, `handoff[:due_at]`
  # hold instants the application already produced, and calling `.getutc` on one of those is
  # formatting rather than decoding. Without this distinction the rule fires on all three and says
  # something false about them.
  def row_rooted?(node)
    return false unless node.is_a?(Array)
    return string_keyed?(node[2]) if node.first == :aref
    return true if node.first == :call && token(node[3], :@ident) == "fetch"

    case node.first
    when :call, :method_add_arg, :method_add_block then row_rooted?(node[1])
    else false
    end
  end

  # A subscript index that is a symbol literal is an in-memory hash; anything else — a string literal,
  # a variable, an expression — is treated as a row, so the rule fails CLOSED on what it cannot read.
  def string_keyed?(index)
    found = true
    each_node(index) { |part| found = false if part.first == :symbol }
    found
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

    # THE ROUND-7 CLASS: a timestamp method on a value read out of a result row. None of these names a
    # constant or uses a protocol symbol, so rules 1 and 2 are blind to every one of them.
    row_rooted = {
      "to_time" => 'row["deadline_at"].to_time',
      "to_datetime" => 'row["deadline_at"].to_datetime',
      "in_time_zone" => 'row["deadline_at"].in_time_zone',
      "acts_like" => 'row["x"].acts_like?(:time)',
      "reflective send" => 'row["x"].send(:strftime, "%s")',
      "chained subscript" => 'gate["a"]["b"].to_time',
      "fetch receiver" => 'row.fetch("deadline_at").to_time',
      "const_get by string" => 'Object.const_get("Time").parse(row["deadline_at"])',
      "class name compare" => 'row["x"].class.name == "Time"',
      "zone parse" => 'ActiveSupport::TimeZone["UTC"].parse(row["x"])'
    }
    row_rooted.each do |label, program|
      expect(violations(program, file: "#{label}.rb")).not_to be_empty,
                                                             "round-7 decoder form undetected: #{label}"
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
      context[:now].utc + (monotonic - context[:entered_monotonic])
      link[:due_at]&.getutc&.iso8601(6)
      row["state_version"].to_i + 1
      gate["sitemap_candidates"].to_s
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
