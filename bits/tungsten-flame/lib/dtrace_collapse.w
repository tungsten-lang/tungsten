# dtrace_collapse.w — Collapse DTrace ustack()/stack() aggregation output
# into folded stacks.
#
# This bit already ingests three profiler formats — Linux `perf script`
# (perf_script.w), Instruments' xctrace XML (xctrace_xml.w), and macOS
# `sample(1)` / `spindump` call graphs (sample_collapse.w). None of them reads
# DTrace, the tracer that ships on macOS, FreeBSD, illumos and Solaris and is
# the one every kernel/systems developer reaches for
# (`dtrace -n 'profile-997 { @[ustack()] = count(); }'`). Its aggregation dump
# is a shape unlike any the other three parse — so nothing here could read it.
# This module is that missing parser, the direct analogue of FlameGraph's
# original `stackcollapse.pl` (the DTrace collapser it was first written for),
# turning a DTrace aggregation printout into the same "root;mid;leaf <count>"
# folded text every other module in this bit speaks.
#
# A DTrace ustack/stack aggregation prints, after Ctrl-C or program exit, one
# block per unique stack: the frames LEAF-FIRST (innermost on top, root at the
# bottom), each indented, then the aggregation COUNT alone on its own indented
# line, with blank lines separating blocks:
#
#   dtrace: description 'profile-997 ' matched 1 probe
#   CPU     ID                    FUNCTION:NAME
#
#                 libc.so.1`__forkx+0xb
#                 bash`make_child+0x17b
#                 bash`execute_command+0x45
#                 bash`main+0xaa5
#                 bash`_start+0x83
#                   1
#
#                 libc.so.1`__read+0xb
#                 bash`main+0xaa5
#                 bash`_start+0x83
#                  12
#
# Unlike perf's per-sample count on the header line and `sample`'s inclusive
# indented tree, DTrace has already aggregated: the trailing number IS the leaf
# (self) count for that exact stack, so no self-time derivation is needed — we
# reverse the leaf-first frames to root-first, join with ";", and attach the
# count. Frames carry a "module`symbol+0xoffset" decoration (kernel stack()
# frames drop the module-external form but keep the "module`symbol"; unresolved
# frames are a bare "0xADDR"); we strip the trailing "+0x..." / "+<decimal>"
# offset, matching stackcollapse.pl and this bit's xctrace "lib`symbol"
# convention. Two stacks that differed only by offset collapse to one and their
# counts sum. Header lines (`dtrace:`, the CPU column header, per-CPU probe
# lines) carry neither a backtick nor a leading "0x" and are ignored, so a raw
# copy-paste straight off a terminal parses cleanly.
#
# Pure text -> folded text (no profiling, no dtrace invocation, no external
# tools): fully unit-testable, and its output pipes straight into every other
# view — --hot, the SVG (-o), --speedscope, --trace-event, --diff,
# --grep/--prune/--subtree, --threshold.
#
# CLI: `flame --collapse-dtrace out.txt` — emits folded stacks to stdout, or to
# -o. A pure-text ingest mode like --diff / --hot / --collapse-sample.

in Tungsten:Flame

+ DtraceCollapse

  # ---- Public entry point ----

  # DTrace aggregation text -> folded-stack string, one "root;...;leaf <count>"
  # line per unique stack, sorted lexicographically for deterministic
  # golden-file output (matching PerfScript / SampleCollapse). Input with no
  # complete stack (frames followed by a count line) yields "".
  -> .collapse(text)
    lines = text.split("\n")
    stacks = {}
    current = []
    i = 0
    n = lines.size()
    while i < n
      stripped = lines[i].strip()
      if stripped.size() == 0
        # Blank line — a block separator. The count line has already flushed
        # the previous stack, so this just guards against a stray frame run
        # bleeding into the next block.
        current = []
      elsif self.all_digits?(stripped)
        # Aggregation count — closes and records the accumulated stack.
        self.flush(current, stripped.to_i(), stacks)
        current = []
      elsif self.frame_line?(stripped)
        current.push(self.parse_frame_name(stripped))
      # else: header / noise (dtrace:, CPU column, per-CPU probe line) — skip.
      i = i + 1
    self.emit(stacks)

  # Record one completed leaf-first stack under its aggregation count: reverse
  # to root-first, join, and sum into any identical stack (offset-stripping can
  # make two raw stacks identical). Empty stacks and non-positive counts are
  # dropped.
  -> .flush(frames, count, stacks)
    if frames.size() == 0
      return
    if count <= 0
      return
    folded = frames.reverse().join(";")
    if stacks.has_key?(folded)
      stacks[folded] = stacks[folded] + count
    else
      stacks[folded] = count

  # ---- Line classification ----

  # True when `stripped` looks like a DTrace stack frame: it names a module and
  # symbol ("module`symbol", so it contains a backtick) or is a bare unresolved
  # address ("0x..."). Header and probe lines match neither.
  -> .frame_line?(stripped)
    if stripped.include?("`")
      return true
    stripped.starts_with?("0x")

  # ---- Frame naming ----

  # Turn a raw frame token ("libc.so.1`__forkx+0xb") into its folded name
  # ("libc.so.1`__forkx") by stripping a trailing "+<offset>". The module and
  # symbol are kept (matching stackcollapse.pl and the xctrace "lib`symbol"
  # convention); a bare address or a symbol with no offset is returned as-is.
  -> .parse_frame_name(raw)
    p = raw.rindex("+")
    if p == nil
      return raw
    suffix = raw.slice(p + 1, raw.size())
    if self.is_offset?(suffix)
      return raw.slice(0, p)
    raw

  # True when `s` is a DTrace frame offset: "0x" followed by hex digits, or a
  # bare run of decimal digits. Guards demangled names whose trailing "+" is
  # part of the symbol (e.g. "operator+") — those have no offset suffix.
  -> .is_offset?(s)
    if s.size() == 0
      return false
    if s.starts_with?("0x")
      return self.all_hex?(s.slice(2, s.size()))
    self.all_digits?(s)

  # ---- Emit ----

  # Render a { stack => count } map to folded text, sorted lexicographically by
  # stack name for deterministic output (matching the other collapsers).
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

  # True when `s` is a non-empty run of hexadecimal digits.
  -> .all_hex?(s)
    if s.size() == 0
      return false
    i = 0
    while i < s.size()
      c = s.slice(i, 1)
      if !"0123456789abcdefABCDEF".include?(c)
        return false
      i = i + 1
    true

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
