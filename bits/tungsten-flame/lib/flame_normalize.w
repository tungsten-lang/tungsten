# flame_normalize.w — Canonicalize a folded profile: collapse recursion and
# merge frame-name variants before viewing.
#
# Every other reshape in this bit works on the SHAPE of the profile — filter
# it by pattern (flame_filter), fold the long tail (flame_threshold), diff two
# runs (flame_diff), or flatten it (hot_frames). None of them attack the axis
# that wrecks a real profile most: the same logical frame appearing under many
# different NAMES, or the same frame appearing hundreds of times in a row.
#
# Two things produce that noise, and this module fixes both as pure
# folded-text -> folded-text transforms (the same "root;mid;leaf <count>" text
# every module here speaks), so the result pipes straight into any other view:
#
#   - .collapse_recursion(text)  — collapse runs of CONSECUTIVE identical
#     frames in each stack (A;A;A;B;B -> A;B). This is the classic
#     `flamegraph.pl --collapse-recursion` transform, and it is the one this
#     bit needs most: its flagship target is the Tungsten compiler, a
#     recursive-descent parser + tree walker, whose stacks look like
#     "parse;parse_expr;parse_expr;parse_expr;...;parse_primary". Left raw, the
#     flame graph is an unreadable staircase of identical slivers; collapsed,
#     the recursive frame becomes one block and the real leaf is visible.
#
#   - .rewrite(text, rules)  — apply regex-free SUBSTRING rewrite rules to
#     every frame name, merging variants that are really one function:
#     monomorphized generics ("Vec<i32>", "Vec<u64>" -> "Vec<T>"), demangled
#     template instantiations, address-suffixed lambdas, or a noisy module
#     prefix. A rule whose replacement is empty ELIDES the substring, and a
#     frame that a rule empties entirely is dropped from the stack — so a
#     rewrite can also strip wrapper/thunk frames. Rules are "old=>new"
#     separated by ";" ("Vec<i32>=>Vec<T>;Vec<u64>=>Vec<T>;__wrap_=>"). ";" is
#     the ideal separator because it never appears inside a frame name (it is
#     the stack separator itself); "=>" maps old to new.
#
# .apply chains them for the CLI (rewrite first so renamed-into-identical
# neighbours then collapse). Every output is re-aggregated (stacks that become
# identical after normalization are summed) and sorted by stack name, matching
# FlameFilter / FlameThreshold / FlameDiff for deterministic golden output.
#
# The substring replace is hand-rolled (index/slice), NOT gsub — the string
# facade miscompiles an empty-literal gsub arg — and it never rescans inserted
# replacement text, so a rule like "a=>aa" cannot loop.
#
# CLI: `flame --collapse-recursion FILE.folded`, `flame --rewrite RULES FILE`
# — pure-text modes like --grep / --threshold (no compile, no profiling) that
# compose with the pattern filters and the threshold collapse; result to
# stdout, or to -o.

in Tungsten:Flame

+ FlameNormalize

  # ---- Parsing ----

  # Parse folded text into { map: { stack => count }, total: N }. Duplicate
  # stacks are summed; lines with no positive count are ignored — matching
  # FlameFilter.parse_folded / FlameThreshold.parse_folded so every module
  # agrees on what a sample is. Count split with rindex(" ") so frame names
  # containing spaces (e.g. "block in Array#tally") survive.
  -> .parse_folded(text)
    map = {}
    total = 0
    lines = text.split("\n")
    i = 0
    while i < lines.size()
      line = lines[i].strip()
      if line.size() > 0
        sp = line.rindex(" ")
        if sp != nil
          stack = line.slice(0, sp)
          count = line.slice(sp + 1, line.size()).to_i()
          if count > 0
            if map.has_key?(stack)
              map[stack] = map[stack] + count
            else
              map[stack] = count
            total = total + count
      i = i + 1
    { map: map, total: total }

  # ---- Recursion collapse ----

  # Collapse runs of consecutive identical frames within each stack, then
  # re-aggregate (stacks that become identical are summed) and sort. Returns
  # folded text. Zero config, deterministic, and count-preserving (nothing is
  # dropped — collapsing only shortens each stack's frame list).
  -> .collapse_recursion(text)
    map = self.parse_folded(text)[:map]
    out = {}
    keys = map.keys()
    i = 0
    while i < keys.size()
      stack = keys[i]
      frames = stack.split(";")
      collapsed = self.dedup_consecutive(frames)
      new_stack = collapsed.join(";")
      if out.has_key?(new_stack)
        out[new_stack] = out[new_stack] + map[stack]
      else
        out[new_stack] = map[stack]
      i = i + 1
    self.emit(out)

  # Drop each frame equal to the one immediately before it (A A A B B -> A B).
  # Non-consecutive repeats are preserved (A B A stays A B A) — matching
  # flamegraph.pl's --collapse-recursion, which folds only direct recursion.
  -> .dedup_consecutive(frames)
    out = []
    i = 0
    while i < frames.size()
      f = frames[i]
      if out.size() == 0 || out.last() != f
        out.push(f)
      i = i + 1
    out

  # ---- Symbol rewrite ----

  # Apply substring rewrite rules to every frame of every stack, then
  # re-aggregate and sort. A frame emptied by its rules is dropped; a stack
  # left with no frames is dropped entirely. Returns folded text. An empty /
  # rule-less spec is a no-op (re-aggregated + sorted).
  -> .rewrite(text, rules_spec)
    rules = self.parse_rules(rules_spec)
    map = self.parse_folded(text)[:map]
    out = {}
    keys = map.keys()
    i = 0
    while i < keys.size()
      stack = keys[i]
      frames = stack.split(";")
      new_frames = []
      fi = 0
      while fi < frames.size()
        nf = self.apply_rules(frames[fi], rules)
        if nf != ""
          new_frames.push(nf)
        fi = fi + 1
      if new_frames.size() > 0
        new_stack = new_frames.join(";")
        if out.has_key?(new_stack)
          out[new_stack] = out[new_stack] + map[stack]
        else
          out[new_stack] = map[stack]
      i = i + 1
    self.emit(out)

  # Apply every rule, in order, to a single frame name.
  -> .apply_rules(frame, rules)
    f = frame
    i = 0
    while i < rules.size()
      r = rules[i]
      f = self.replace_all(f, r[0], r[1])
      i = i + 1
    f

  # Parse a rule spec ("old=>new;old2=>new2") into a list of [old, new] pairs.
  # Rules split on ";" (never part of a frame name); each rule splits on its
  # first "=>". Whitespace around the whole rule token is trimmed for CLI
  # ergonomics; the old/new substrings themselves are used verbatim. Rules with
  # an empty `old` are skipped (an empty pattern would match everywhere). A
  # nil / empty spec yields no rules.
  -> .parse_rules(rules_spec)
    rules = []
    if rules_spec == nil
      return rules
    s = rules_spec.to_s()
    if s == ""
      return rules
    parts = s.split(";")
    i = 0
    while i < parts.size()
      p = parts[i].strip()
      arrow = p.index("=>")
      if arrow != nil
        old = p.slice(0, arrow)
        new = p.slice(arrow + 2, p.size())
        if old != ""
          rules.push([old, new])
      i = i + 1
    rules

  # Replace every non-overlapping occurrence of `old` with `new` in `s`
  # (hand-rolled — the string facade miscompiles an empty-literal gsub arg).
  # An empty `old` is a no-op. Inserted replacement text is never rescanned, so
  # a rule like "a=>aa" terminates.
  -> .replace_all(s, old, new)
    if old == ""
      return s
    out = ""
    rest = s
    idx = rest.index(old)
    while idx != nil
      out = out + rest.slice(0, idx) + new
      rest = rest.slice(idx + old.size(), rest.size())
      idx = rest.index(old)
    out + rest

  # ---- CLI pipeline ----

  # Normalize for the CLI: rewrite frame names first (so variants merge), then
  # collapse recursion (so neighbours renamed to the same name also fold). Each
  # step is skipped when not requested. Returns folded text, so it composes
  # with the pattern filters and the threshold collapse.
  -> .apply(text, do_recursion, rules_spec)
    result = text
    if rules_spec != nil && rules_spec.to_s() != ""
      result = self.rewrite(result, rules_spec)
    if do_recursion
      result = self.collapse_recursion(result)
    result

  # ---- Emit ----

  # Render a { stack => count } map back to folded text, one "stack count" line
  # per stack, sorted lexicographically by stack name for deterministic output
  # (matching FlameFilter.emit / FlameThreshold.emit).
  -> .emit(map)
    keys = self.sort_strings(map.keys())
    out = []
    i = 0
    while i < keys.size()
      k = keys[i]
      out.push(k + " " + map[k].to_s())
      i = i + 1
    out.join("\n")

  # Lexicographic insertion sort (deterministic golden output).
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
