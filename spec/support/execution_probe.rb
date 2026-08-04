# frozen_string_literal: true

# DID THIS PROOF EXECUTE THE LINE IT NAMES? (round 8, R8-3 and R8-4.)
#
# Round 8's finding was not that the controls were wrong. Three lenses independently verified the
# shipped code correct on every path they exercised. What failed was the evidence: PROOF 168
# terminalized the Crawl before calling `advance`, so the guard it named was never reached and both
# of its assertions were satisfied by an authorization denial nine lines earlier; and
# `ActivateCrawlPolicy`'s post-wait recheck had no proof at all — deleting it left 388 examples
# green.
#
# Assertions on outcomes cannot tell those cases apart. "The command was refused" is true when the
# recheck refused it and equally true when a validation branch refused it first, and a proof that
# cannot distinguish them proves whichever one happens to run.
#
# So this reports what actually executed. `TracePoint` is Ruby's own execution record: the lines it
# reports are the lines the interpreter ran, in this process, during this block. Nothing is inferred
# from arguments, return values or database state.
#
#   executed = ExecutionProbe.lines("app/workflows/wf005/handlers/activate_crawl_policy.rb") { ... }
#   expect(executed).to include(103)   # the recheck ran
#
# COST. A `:line` trace is enabled only for the block and filters on absolute path, so it is paid by
# the handful of examples that need it and by nothing else.
module ExecutionProbe
  module_function

  # Every line of `relative_paths` executed inside the block, as { relative_path => Set(line) }.
  def executed(*relative_paths)
    roots = relative_paths.to_h { |path| [Rails.root.join(path).to_s, path] }
    seen = Hash.new { |h, k| h[k] = Set.new }
    trace = TracePoint.new(:line) do |tp|
      relative = roots[tp.path]
      seen[relative] << tp.lineno if relative
    end
    trace.enable
    begin
      yield
    ensure
      trace.disable
    end
    seen
  end

  # The lines of ONE file executed inside the block.
  def lines(relative_path, &) = executed(relative_path, &).fetch(relative_path, Set.new)

  # The 1-based line numbers in `relative_path` whose source matches `pattern`. This is what lets a
  # proof name a CONTROL rather than a line number: the assertion stays true when the file moves, and
  # fails loudly when the control it names is deleted or renamed.
  def line_of(relative_path, pattern)
    matches = Rails.root.join(relative_path).read.lines.each_with_index.filter_map do |line, index|
      index + 1 if line.match?(pattern) && !line.strip.start_with?("#")
    end
    raise "no line in #{relative_path} matches #{pattern.inspect}" if matches.empty?
    raise "#{matches.length} lines in #{relative_path} match #{pattern.inspect}" if matches.length > 1

    matches.first
  end
end
