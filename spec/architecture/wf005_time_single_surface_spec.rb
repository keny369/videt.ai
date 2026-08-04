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
  # THE TIMESTAMP CLASSES THEMSELVES — the single runtime source both halves of rule 3 are derived
  # from. Their methods become the vocabulary; their NAMES become the decoder-class limb. One list of
  # classes, not two lists of spellings, so the two halves cannot drift apart.
  def timestamp_classes = [Time, DateTime, Date, ActiveSupport::TimeWithZone, ActiveSupport::TimeZone]
  def timestamp_class_names = timestamp_classes.map(&:name).to_set

  def timestamp_vocabulary
    @timestamp_vocabulary ||= (
      timestamp_classes.flat_map { |k| k.instance_methods + k.methods }.uniq -
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
    rows = row_locals(tree)
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

      # RULE 3. A TIMESTAMP METHOD CALLED ON A VALUE THAT IS NOT PROVABLY IN MEMORY (round 8, R8-6).
      #
      # THE RECEIVER IS WHAT DISTINGUISHES DECODING FROM FORMATTING, and rules 1 and 2 cannot see it.
      # `row["deadline_at"].to_time` names no constant and uses no symbol, and IS the
      # connection-dependent decode this module exists to own; `now.getutc` formats an instant the
      # application already holds, and the corpus does nine of those legitimately.
      #
      # ROUND 7 WROTE THIS AS A DENYLIST OF RECEIVER SHAPES AND ROUND 8 WALKED THIRTY OF FORTY-ONE
      # FORMS PAST IT. Both of its axes enumerated: the CALL axis fired only on Ripper's `:call`, so
      # `row["x"].strftime "%s"` — a parenless call with arguments, which is `:command_call` — escaped,
      # which is round 6's escape #3 recurring one rule later inside the rule written to close it. The
      # RECEIVER axis listed three shapes and four node kinds, so `row.dig("x")`, `(row["x"])` and
      # `d = row["x"]; d.to_time` all escaped. The answer to a list that can be out-enumerated is not a
      # longer list, so BOTH AXES ARE INVERTED HERE:
      #
      #   * A CALL IS RECOGNISED BY ITS OPERATOR, not by its node kind. Every explicit-receiver call in
      #     Ruby is `receiver <op> name` where `<op>` is one of `.`, `&.` or `::` — a closed set the
      #     LANGUAGE defines, not one this file invents — so any node of that shape is a call whatever
      #     Ripper labels it, including kinds that do not exist yet.
      #   * A RECEIVER IS SAFE ONLY IF IT CAN BE PROVED IN MEMORY. Locals, instance variables,
      #     symbol-keyed subscripts of those, literals, and chains of timestamp methods over them.
      #     ANYTHING ELSE IS A FINDING, including shapes this file has never been shown. A new escape
      #     is therefore caught by default and a new false positive is a visible, fixable failure —
      #     which is the direction a fitness check must fail in.
      next unless (call = explicit_call(node))

      receiver, method = call
      next unless timestamp_vocabulary.include?(method)

      # A TIMESTAMP METHOD ON A CLASS IS A DECODER CALL. `Date.parse(row["x"])` reaches the same
      # connection-dependent decode through a class the corpus legitimately uses for other purposes,
      # which is why `Date` cannot simply join `banned_constants`: `Date.new(t.year, t.month, 1)` is
      # four legitimate call sites. The distinction is the METHOD, and there is exactly one authorised
      # decoder.
      if (constant = constant_name(receiver))
        # ONLY A TIMESTAMP CLASS DECODES AN INSTANT. `JSON.parse` and `Digest::SHA256.digest` share
        # method names with the vocabulary and decode nothing about time; the classes that do are the
        # ones the vocabulary itself is derived from, which is why there is no second list to keep.
        next unless timestamp_class_names.include?(constant)

        findings << "#{file}:#{line_of(node[3])} calls #{constant}.#{method}, which decodes an instant " \
                    "outside Platform::PgInstant"
        next
      end
      next if in_memory?(receiver, rows)

      findings << "#{file}:#{line_of(node[3])} calls ##{method} on a value that is not provably an " \
                  "in-memory instant; PostgreSQL instants are decoded only by Platform::PgInstant"
    end
    findings.uniq
  end

  # THE ONE AUTHORISED DECODER. Every other constant calling a timestamp method is building an
  # instant from something this module has not decoded.
  CANONICAL_DECODER = "Platform::PgInstant"

  # Ruby's complete set of explicit-receiver call operators. A LANGUAGE FACT, not a list this file
  # maintains: there is no fourth way to write `receiver <op> method`.
  CALL_OPERATORS = [".", "&.", "::"].freeze

  # `[kind, receiver, operator, name]` for any node that calls a method on an explicit receiver, or
  # nil. Recognised by the OPERATOR, so `:call`, `:command_call` and any node kind a future Ripper
  # introduces with the same shape are all covered without naming any of them.
  def explicit_call(node)
    return nil unless node.is_a?(Array) && node.length >= 4

    operator = node[2]
    text = operator.is_a?(Array) ? token(operator) : operator.to_s
    return nil unless CALL_OPERATORS.include?(text.to_s)

    name = %i[@ident @const @kw @op].filter_map { |kind| token(node[3], kind) }.first
    return nil if name.nil?

    [node[1], name]
  end

  # Can this expression be PROVED to hold a value the application already has in memory?
  #
  # THE ONE STRUCTURAL FACT THIS RESTS ON: a `PG::Result` tuple is STRING-KEYED, and every in-memory
  # structure in this workflow is symbol-keyed. So a name that is string-subscripted anywhere in a
  # file is a database row in that file — `row["x"]`, `crawl["deadline_at"]`, `gate["sitemap_state"]`
  # — and everything reached THROUGH it is row data, whether by subscript, by `fetch`, by `dig`, by a
  # method this file has never heard of, or through a local it was bound to on the way. Everything
  # else — locals, parameters, instance variables, literals, and what application objects return from
  # their own accessors — is a value the application already holds, and formatting one is not decoding.
  #
  # FAIL CLOSED ON THE ROW AXIS. Round 7's predicate asked "is this receiver one of three row shapes?"
  # and answered no for everything it had not been taught, so `row.dig("x")`, `(row["x"])` and
  # `d = row["x"]; d.to_time` all walked past it. This asks the opposite question, so an unfamiliar
  # way of reaching into a row is a finding by default and only a NEW SHAPE OF IN-MEMORY VALUE can
  # produce a false positive — which is a visible failure someone fixes, not a silent hole.
  def in_memory?(node, rows = Set.new)
    return false unless node.is_a?(Array)

    case node.first
    when :var_ref, :var_field, :vcall
      name = %i[@ident @ivar @gvar @cvar].filter_map { |kind| token(node[1], kind) }.first
      return !rows.include?(name) unless name.nil?

      !constant_name(node).nil?
    when :const_ref, :top_const_ref, :const_path_ref then true
    # A parenthesised expression is its content: `(row["x"]).to_time` walked past round 7's rule
    # because a `:paren` node terminated the recursion.
    when :paren then in_memory?(unwrap_paren(node), rows)
    # A SYMBOL-KEYED SUBSCRIPT IS AN IN-MEMORY HASH — `context[:now]`, `link[:due_at]` — and a
    # subscript by anything else is a row read.
    when :aref then symbol_keyed?(node[2]) && in_memory?(node[1], rows)
    when :string_literal, :symbol_literal, :dyna_symbol, :array, :hash, :regexp_literal,
         :@int, :@float, :@regexp_end, :hashliteral then true
    # A CALL ON SELF IS THE APPLICATION'S OWN. `fetch(context, ...)`, `measure(outcome)` and
    # `link_next(...)` return values this object built; the receiver is `self`, which is in memory by
    # definition, so treating them as foreign would flag every intermediate a method computes.
    when :fcall, :command, :command_call_no_receiver then true
    # A BINARY OPERATOR IS A METHOD CALL ON ITS LEFT OPERAND, and the result is that operand's kind:
    # `now + policy[:bounds]["wall_clock_minutes"]["hard"]` is an instant the application computed,
    # even though a number came out of a string-keyed hash on the way. Following the receiver here is
    # the same rule as following it for `.getutc`, applied to the same thing spelled differently.
    when :binary then in_memory?(node[1], rows)
    when :unary then in_memory?(node[2], rows)
    when :method_add_arg, :method_add_block
      inner = node[1]
      next_is_fcall = inner.is_a?(Array) && %i[fcall command].include?(inner.first)
      next_is_fcall || in_memory?(inner, rows)
    else
      call = explicit_call(node)
      return false if call.nil?

      # A CALL IS AS PROVABLE AS ITS RECEIVER. `command.due_at.getutc` formats a value the command
      # already holds; `row.dig("x").to_time` decodes one the connection just produced. The rule does
      # not need to know what `due_at` or `dig` do — only where the value came from.
      in_memory?(call.first, rows)
    end
  end

  def unwrap_paren(node)
    inner = node[1]
    inner = inner.first if inner.is_a?(Array) && inner.first.is_a?(Array)
    inner
  end

  # An index that IS a symbol literal — the only subscript form this rule treats as in memory.
  def symbol_keyed?(index)
    found = false
    each_node(index) { |part| found = true if part.first == :symbol }
    found
  end

  # THE NAMES THAT HOLD DATABASE ROWS IN THIS PROGRAM, to a fixed point.
  #
  # Seeded by the structural fact: a name that is STRING-SUBSCRIPTED is a `PG::Result` tuple. Then
  # closed over assignment, so a value carried out of a row through one or more bindings is still row
  # data — `d = row["x"]` severed round 7's predicate entirely, and `a = row["x"]; b = a` severs any
  # rule that follows only one hop.
  def row_locals(tree)
    rows = Set.new
    each_node(tree) do |node|
      next unless node.first == :aref
      next if symbol_keyed?(node[2])

      name = %i[@ident @ivar @gvar @cvar].filter_map { |kind| token(node[1].is_a?(Array) ? node[1][1] : nil, kind) }.first
      rows << name unless name.nil?
    end

    # A BLOCK PARAMETER BOUND FROM A ROW VALUE IS A ROW VALUE: `crawl["x"].then { |v| v.to_time }`
    # hands the row value straight to `v`, and a rule that followed only assignments would not see it.
    each_node(tree) do |node|
      next unless node.first == :method_add_block
      next if in_memory?(node[1], rows)

      each_node(node[2]) do |part|
        next unless part.first == :params

        each_node(part) { |leaf| (name = token(leaf, :@ident)) && rows << name }
      end
    end

    loop do
      before = rows.size
      each_node(tree) do |node|
        next unless %i[assign opassign].include?(node.first)

        name = %i[@ident @ivar @gvar @cvar].filter_map { |kind| token(node[1].is_a?(Array) ? node[1][1] : nil, kind) }.first
        next if name.nil? || rows.include?(name)

        rows << name unless in_memory?(node[2], rows)
      end
      break if rows.size == before
    end
    rows
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

  # ---- the forms, INJECTED INTO A REAL TRACKED CORPUS FILE (round 8, R8-6 and R8-7) -------------
  #
  # ROUND 8 RECORDED TWO SEPARATE FAULTS HERE. The rule let thirty of forty-one bypass forms into the
  # real tracked corpus with the check green; and the record claimed "16 forms injected into the real
  # corpus" when the examples evaluated synthetic programs as strings and injected nothing.
  #
  # A ONE-LINE SYNTHETIC PROGRAM CANNOT TEST THIS RULE, and that is not a detail. Rule 3 decides by
  # PROVENANCE: `crawl["deadline_at"]` is what makes `crawl` a database row, so `crawl.dig(...)` in a
  # program that never subscripts `crawl` is genuinely undecidable and a detector that guessed would
  # be guessing in production too. So each form is inserted into the REAL source of a REAL tracked
  # file, inside a REAL method, where the surrounding code establishes what those names hold — and the
  # scan that runs is the same `violations` the corpus proof runs, over the same file name.
  ANCHOR_FILE = "app/workflows/wf005/crawl_driver.rb"
  # A line inside `advance_pass`, after the pass has loaded its row. Chosen by CONTENT, so it moves
  # with the file and fails loudly if the method is restructured rather than injecting into nowhere.
  ANCHOR_LINE = "crawl_id = entry[\"crawl_id\"]"

  # The tracked file's real source with `form` inserted after the anchor, and the injected line's
  # 1-based number.
  def inject(form)
    source = Rails.root.join(ANCHOR_FILE).read
    lines = source.lines
    index = lines.index { |line| line.include?(ANCHOR_LINE) }
    raise "anchor #{ANCHOR_LINE.inspect} is gone from #{ANCHOR_FILE}" if index.nil?

    lines.insert(index + 1, "        #{form}\n")
    [lines.join, index + 2]
  end

  def findings_for(form)
    source, line = inject(form)
    raise "injecting #{form.inspect} produced unparseable Ruby" if Ripper.sexp(source).nil?

    [violations(source, file: ANCHOR_FILE), line]
  end

  it "proves the corpus injection reaches the rule at all" do
    # NON-VACUITY OF THE HARNESS ITSELF, before anything is claimed about the forms. The unmodified
    # file is clean, the anchor exists, and a form injected at it lands on the line this says it does.
    source, line = inject('crawl["deadline_at"].to_time')
    expect(violations(Rails.root.join(ANCHOR_FILE).read, file: ANCHOR_FILE)).to be_empty
    expect(source.lines[line - 1]).to include("to_time")
    expect(violations(source, file: ANCHOR_FILE).grep(/:#{line} /)).not_to be_empty
  end

  # EVERY BYPASS FORM ROUND 8 WALKED PAST THE RULE, AND THE CLASSES THEY CAME FROM.
  #
  # `crawl` and `entry` are the anchor file's own row locals — the file subscripts both — so these
  # are the shapes as they would really appear, not a synthetic `row`.
  {
    # Round 6's escapes, which round 8 found recurring one rule later.
    "parenless call with arguments (command_call)" => 'crawl["deadline_at"].strftime "%s"',
    "parenless duck-type test" => 'crawl["deadline_at"].acts_like? :time',
    "parenless reflective send" => 'crawl["deadline_at"].send :strftime, "%s"',
    # Round 7's decoder forms.
    "to_time" => 'crawl["deadline_at"].to_time',
    "to_datetime" => 'crawl["deadline_at"].to_datetime',
    "in_time_zone" => 'crawl["deadline_at"].in_time_zone',
    "acts_like with parentheses" => 'crawl["deadline_at"].acts_like?(:time)',
    "reflective send with parentheses" => 'crawl["deadline_at"].send(:strftime, "%s")',
    "chained subscript" => 'entry["a"]["b"].to_time',
    "fetch receiver" => 'crawl.fetch("deadline_at").to_time',
    "const_get by string" => 'Object.const_get("Time").parse(crawl["deadline_at"])',
    "class name compare" => 'crawl["deadline_at"].class.name == "Time"',
    "zone parse" => 'ActiveSupport::TimeZone["UTC"].parse(crawl["deadline_at"])',
    # Round 8's escapes, each one the reason a whole class of shapes escaped.
    "dig receiver" => 'crawl.dig("deadline_at").to_time',
    "parenthesised receiver" => '(crawl["deadline_at"]).to_time',
    "intermediate binding" => 'd = crawl["deadline_at"]; d.to_time',
    "two-hop binding" => 'a = crawl["deadline_at"]; b = a; b.to_time',
    "Date parser" => 'Date.parse(crawl["deadline_at"])',
    "Date class method" => 'Date.iso8601(crawl["deadline_at"])',
    # And forms constructed from the RULE rather than from its implementation, which is the property
    # that distinguishes a structural check from a longer denylist.
    "safe navigation" => 'crawl["deadline_at"]&.to_time',
    "safe navigation after binding" => 'e = crawl["deadline_at"]; e&.getutc',
    "block form" => 'crawl["deadline_at"].then { |v| v.to_time }',
    "values_at receiver" => 'crawl.values_at("deadline_at").first.to_time',
    "double parens" => '((crawl["deadline_at"])).to_time',
    "scope resolution call" => 'crawl["deadline_at"]::to_time',
    "method object" => 'crawl["deadline_at"].method(:to_time)',
    "public_send" => 'crawl["deadline_at"].public_send(:iso8601)',
    "respond_to on a row value" => 'crawl["deadline_at"].respond_to?(:getutc)',
    "strptime on a row value" => 'crawl["deadline_at"].strptime("%s")',
    "xmlschema on a row value" => 'crawl["deadline_at"].xmlschema',
    "httpdate on a row value" => 'crawl["deadline_at"].httpdate',
    "localtime on a row value" => 'crawl["deadline_at"].localtime',
    "getlocal on a row value" => 'crawl["deadline_at"].getlocal',
    "variable-keyed subscript" => 'crawl[column].to_time',
    "interpolated key" => 'crawl["deadline_#{suffix}"].to_time',
    "chained through a method" => 'crawl["deadline_at"].to_s.to_time',
    "row value through a hop and a paren" => 'f = (crawl["deadline_at"]); f.to_datetime',
    "aref on a fetch" => 'crawl.fetch("row")["deadline_at"].to_time',
    # SHAPES THE RULE HAS NO CASE FOR AT ALL, which is what "fails closed" has to mean if it means
    # anything: a receiver the analysis cannot classify is foreign, not assumed safe.
    "conditional receiver" => '(entry["a"] ? crawl["deadline_at"] : crawl["started_at"]).to_time',
    "begin-block receiver" => 'begin; crawl["deadline_at"]; end.to_time'
  }.each do |label, form|
    it "catches a decoder injected into the real corpus: #{label}" do
      findings, line = findings_for(form)

      expect(findings.grep(/:#{line} /)).not_to be_empty,
                                                "#{label} was injected at #{ANCHOR_FILE}:#{line} as " \
                                                "`#{form}` and the rule did not fire on it. " \
                                                "Findings: #{findings.inspect}"
    end
  end

  # AND THE FORMS THAT MUST NOT FIRE, injected the same way. A rule that caught everything would pass
  # every example above and be useless, and round 6 recorded that a check people route around is worse
  # than none. Each of these is a FORMAT of an instant the application already holds.
  {
    "local instant" => 'now.getutc.iso8601(6)',
    "safe-navigated local" => 'due_at&.getutc',
    "symbol-keyed hash" => 'context[:now].utc',
    "symbol-keyed with safe navigation" => 'link[:due_at]&.getutc&.iso8601(6)',
    "symbol-keyed nested" => 'handoff[:due_at].iso8601(6)',
    "the canonical decoder" => 'Platform::PgInstant.utc(crawl["deadline_at"])',
    "the canonical elapsed measure" => 'Platform::PgInstant.elapsed_minutes(crawl["started_at"], now)',
    "the canonical boundary" => 'Platform::PgInstant.expired?(crawl["deadline_at"], at: now)',
    "an integer conversion on a row value" => 'crawl["state_version"].to_i + 1',
    "a string conversion on a row value" => 'entry["canonical_url"].to_s',
    "a month bucket from an application instant" => 'Date.new(now.year, now.month, 1).iso8601',
    "an accessor chain on a command" => 'command.due_at.getutc.iso8601(6)',
    "a receiverless call" => 'stage_instant(latest).iso8601(6)',
    "a regexp test" => '/\A\d+\z/.match?(raw)',
    "a duck-type test on a domain object" => 'outcome.respond_to?(:latency_ms)'
  }.each do |label, form|
    it "does not fire on a legitimate form injected into the real corpus: #{label}" do
      findings, line = findings_for(form)

      expect(findings.grep(/:#{line} /)).to be_empty,
                                            "#{label} injected at #{ANCHOR_FILE}:#{line} as `#{form}` " \
                                            "was reported as a decoder: #{findings.grep(/:#{line} /).inspect}"
    end
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
    # the committed detector, and each is a rule-1 or rule-2 matter, which needs no file context.
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

  it "proves the call detection rests on the language's operators, not on node kinds" do
    # THE INVERSION ROUND 8 REQUIRED, ASSERTED DIRECTLY. Ruby has exactly three explicit-receiver call
    # operators; the rule keys on those rather than on Ripper's labels, which is why a parenless call
    # (`:command_call`) is caught by the same code that catches a parenthesised one (`:call`) with
    # nothing naming either.
    expect(CALL_OPERATORS).to contain_exactly(".", "&.", "::")
    detector = File.read(__FILE__)
    body = detector[detector.index("def explicit_call")..detector.index("# Can this expression be PROVED")]
    expect(body).not_to include(":command_call")
    expect(body).not_to include(":method_add_arg")
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
