# sample_collapse.w — Collapse macOS `sample(1)` / `spindump` call graphs
# into folded stacks.
#
# This bit already ingests two profiler formats — Linux `perf script`
# (perf_script.w) and Instruments' xctrace XML (xctrace_xml.w) — but both are
# wired only into the internal Sampler pipeline. Neither covers the profiler
# every Mac already has: Apple's built-in `sample(1)` (and its sibling
# `spindump`), which any developer can run against a live pid with zero setup
# ("sample MyApp 5 -f out.txt"). Its output is an INDENTED CALL-GRAPH TREE, a
# different shape from perf's leaf-to-root sample blocks and xctrace's XML —
# so nothing here could read it. This module is that missing parser (the
# analogue of FlameGraph's `stackcollapse-sample.pl`), turning a `sample` /
# `spindump` "Call graph:" section into the same "root;mid;leaf <count>" folded
# text every other module in this bit speaks.
#
# A `sample` call graph looks like (indentation + a "+" marker mark depth,
# and the leading number on each line is that frame's INCLUSIVE count):
#
#   Call graph:
#       2276 Thread_2b0e   DispatchQueue_1: com.apple.main-thread  (serial)
#       + 2276 start (in dyld) + 462  [0x18a0b5f50]
#       +   2276 main (in flame_demo) + 40  [0x1000037a8]
#       +     2000 compute (in flame_demo) + 20  [0x100003800]
#       +       2000 inner (in flame_demo) + 8  [0x100003900]
#       +     276 helper (in flame_demo) + 12  [0x100003a00]
#   Total number in stack ...
#
# Folded stacks want per-LEAF (self) counts, but a call graph gives INCLUSIVE
# counts. We recover self time the standard way: a frame's self = its inclusive
# count minus the sum of its direct children's inclusive counts. Walking the
# indented tree with a stack, we subtract each child's count from its parent as
# we descend and emit a "root;...;frame <self>" line for every frame whose self
# is positive when it closes (a shallower-or-equal line arrives, or EOF). Frames
# that recurse across sibling subtrees are summed. The thread line is the root
# frame, so stacks are naturally grouped per thread.
#
# Robust to format variants: depth is the raw leading-column at which the count
# begins (spaces plus any "+ ! *" tree markers), so 2-space `sample` indent and
# marker-prefixed `spindump` indent both work — only relative order matters.
# Symbol extraction cuts a decorated line ("start (in dyld) + 462 [0x...]", or
# spindump's "start + 462 (dyld + 25627) [0x...]") at the first of " (in ", a
# " + <offset>", a " [0x..." address, or a two-space label gap — matching the
# frame names the rest of the bit produces.
#
# Pure text -> folded text (no profiling, no atos, no external tools): fully
# unit-testable, and its output pipes straight into every other view — --hot,
# the SVG (-o), --speedscope, --diff, --grep/--prune/--subtree.
#
# CLI: `flame --collapse-sample sample.txt` — emits folded stacks to stdout, or
# to -o. A pure-text ingest mode like --diff / --hot.

in Tungsten:Flame

+ SampleCollapse

  # ---- Public entry point ----

  # macOS `sample` / `spindump` text -> folded-stack string, one
  # "root;...;leaf <count>" line per stack with a positive self count, sorted
  # lexicographically for deterministic golden-file output (matching
  # PerfScript.collapse). Empty / call-graph-less input yields "".
  -> .collapse(text)
    lines = text.split("\n")
    start_i = self.section_start(lines)
    stacks = {}
    indents = []
    names = []
    selfs = []
    i = start_i
    while i < lines.size()
      line = lines[i]
      if self.section_end?(line)
        break
      parsed = self.parse_line(line)
      if parsed != nil
        self.push_frame(indents, names, selfs, parsed, stacks)
      i = i + 1
    while indents.size() > 0
      self.finish_top(indents, names, selfs, stacks)
    self.emit(stacks)

  # ---- Tree walk ----

  # Open a frame: close any frames at depth >= this one (they are complete),
  # subtract this frame's inclusive count from its parent's running self, then
  # push it. `parsed` is { indent:, count:, name: }.
  -> .push_frame(indents, names, selfs, parsed, stacks)
    d = parsed[:indent]
    c = parsed[:count]
    while indents.size() > 0 && indents.last() >= d
      self.finish_top(indents, names, selfs, stacks)
    if selfs.size() > 0
      li = selfs.size() - 1
      selfs[li] = selfs[li] - c
    indents.push(d)
    names.push(parsed[:name])
    selfs.push(c)

  # Close the top frame: if its self count is positive, emit the current stack
  # path (root -> this frame) with that count, summing frames that recur across
  # subtrees. Then pop it off the parallel stacks.
  -> .finish_top(indents, names, selfs, stacks)
    li = selfs.size() - 1
    sc = selfs[li]
    if sc > 0
      folded = names.join(";")
      if stacks.has_key?(folded)
        stacks[folded] = stacks[folded] + sc
      else
        stacks[folded] = sc
    indents.pop
    names.pop
    selfs.pop

  # ---- Line parsing ----

  # Parse one call-graph line into { indent:, count:, name: }, or nil for a
  # non-frame line (blank, header, annotation). A frame line is: leading
  # indent/markers, a decimal inclusive count, a space, then the decorated
  # symbol.
  -> .parse_line(line)
    indent = self.leading_indent(line)
    rest0 = line.slice(indent, line.size())
    sp = rest0.index(" ")
    if sp == nil
      return nil
    count_str = rest0.slice(0, sp)
    if !self.all_digits?(count_str)
      return nil
    count = count_str.to_i()
    symbol_part = rest0.slice(sp + 1, rest0.size()).strip()
    name = self.extract_symbol(symbol_part)
    if name.size() == 0
      return nil
    { indent: indent, count: count, name: name }

  # Number of leading indent/tree-marker characters before content begins. The
  # marker set covers `sample` ("+") and `spindump` ("!" / "*") tree glyphs plus
  # spaces; the count is used only as an ordinal (deeper == larger), so the
  # exact per-level step never matters.
  -> .leading_indent(line)
    i = 0
    n = line.size()
    while i < n
      c = line.slice(i, 1)
      if c == " " || c == "+" || c == "!" || c == "*"
        i = i + 1
      else
        break
    i

  # Extract the symbol name from the post-count remainder, cutting at the first
  # decoration delimiter that appears: " (in <lib>)", a " + <offset>", a
  # " [0x<addr>]", or a two-space label gap (thread/queue lines). A bare symbol
  # with no decoration is returned as-is.
  -> .extract_symbol(s)
    cut = s.size()
    a = s.index(" (in ")
    if a != nil && a < cut
      cut = a
    b = s.index(" \[0x")
    if b != nil && b < cut
      cut = b
    off = self.offset_index(s)
    if off != nil && off < cut
      cut = off
    gap = s.index("  ")
    if gap != nil && gap < cut
      cut = gap
    s.slice(0, cut).strip()

  # Index of the " + <offset>" delimiter — the first " + " immediately followed
  # by a digit (so demangled "operator+ (in ...)" style names aren't cut). nil
  # when absent.
  -> .offset_index(s)
    idx = s.index(" + ")
    if idx == nil
      return nil
    nextc = s.slice(idx + 3, 1)
    if self.is_digit?(nextc)
      return idx
    nil

  # ---- Section boundaries ----

  # Index of the first line after a "Call graph:" header, or 0 when there is no
  # header (so a hand-trimmed snippet of just the graph lines parses too).
  -> .section_start(lines)
    i = 0
    while i < lines.size()
      if lines[i].include?("Call graph")
        return i + 1
      i = i + 1
    0

  # True when `line` opens one of the sections `sample` prints after the call
  # graph, marking the end of the frames we care about. Blank lines inside the
  # graph do not end it.
  -> .section_end?(line)
    t = line.strip()
    if t.size() == 0
      return false
    t.starts_with?("Total number in stack") || t.starts_with?("Sort by top of stack") || t.starts_with?("Binary Images")

  # ---- Emit ----

  # Render a { stack => count } map to folded text, sorted lexicographically by
  # stack name for deterministic output (matching PerfScript / FlameFilter).
  -> .emit(stacks)
    keys = self.sort_strings(stacks.keys())
    out = []
    i = 0
    while i < keys.size()
      k = keys[i]
      out.push(k + " " + stacks[k].to_s())
      i = i + 1
    out.join("\n")

  # ---- Helpers ----

  # True when `s` is a non-empty run of decimal digits.
  -> .all_digits?(s)
    if s.size() == 0
      return false
    i = 0
    while i < s.size()
      c = s.slice(i, 1)
      if !"0123456789".include?(c)
        return false
      i = i + 1
    true

  # True when the single-character string `ch` is a decimal digit. Guards the
  # empty string, which .include? would otherwise report as a substring match.
  -> .is_digit?(ch)
    ch.size() > 0 && "0123456789".include?(ch)

  # Lexicographic insertion sort (deterministic, golden-file-friendly),
  # matching the sort the other modules use.
  -> .sort_strings(xs)
    arr = []
    i = 0
    while i < xs.size()
      arr.push(xs[i])
      i = i + 1
    j = 1
    while j < arr.size()
      key = arr[j]
      k = j - 1
      while k >= 0 && arr[k] > key
        arr[k + 1] = arr[k]
        k = k - 1
      arr[k + 1] = key
      j = j + 1
    arr
