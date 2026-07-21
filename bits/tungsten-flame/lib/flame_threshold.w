# flame_threshold.w — Minimum-width threshold pruning: fold the long tail
# of tiny frames into a single "(other)" node.
#
# Every other reshape in this bit is either a picture (flame_svg), an export
# (speedscope), an analysis (hot_frames / flame_diff), or a PATTERN filter
# (flame_filter's grep/prune/subtree). None of them attack the other axis a
# real profile forces on you: the long tail. A production stack profile has a
# handful of hot frames and hundreds of frames holding a fraction of a percent
# each — dispatch stubs, one-off allocations, unresolved addresses. They
# swamp the flame graph with hairline slivers, bloat a speedscope export, and
# bury the signal. Every serious profiler prunes them: flamegraph.pl has
# `--minwidth`, pprof has `-nodefraction`, perf report has `--percent-limit`.
#
# This module is that operation as a first-class, testable, folded-text →
# folded-text transform. It computes each node's INCLUSIVE weight (the sum of
# every stack that flows through that node's root→node path), and folds any
# node below a threshold percentage — together with its whole subtree — into a
# single "(other)" child of its last surviving ancestor. Nothing is dropped:
# the folded counts are re-homed onto "(other)", so the grand total is
# preserved exactly (unlike a plain `grep`, which deletes samples). Under a
# hot parent, its swarm of tiny children collapses into one "(other)" block.
#
# Because it emits the same "root;mid;leaf <count>" text every module here
# speaks — re-aggregated (identical rewritten stacks summed) and sorted by
# stack name, matching FlameFilter / FlameDiff for deterministic golden output
# — its result pipes straight into any other view: SVG, speedscope, --hot, a
# diff, or another filter.
#
# CLI: `flame --threshold PCT FILE.folded` — a pure-text mode (no compile, no
# profiling) like --grep / --diff / --hot. It also composes with the pattern
# filters (`flame --subtree parse --threshold 1 FILE`): the filter reshapes,
# then the threshold collapses the survivors' tail. PCT accepts one decimal
# ("0.5", "2", "1.5"); result to stdout, or to -o.

in Tungsten:Flame

+ FlameThreshold

  # ---- Parsing ----

  # Parse folded text into { map: { stack => count }, total: N }. Duplicate
  # stacks are summed; lines with no positive count are ignored — matching
  # FlameFilter.parse_folded / FlameDiff.parse_folded so every module agrees
  # on what a sample is. Count split with rindex(" ") so frame names
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

  # ---- Inclusive node weights ----

  # Inclusive weight of every call-tree node, keyed by its full root→node
  # path string ("main", "main;a", "main;a;b", ...): the sum of the counts of
  # all stacks carrying that prefix. One pass over the stacks accumulates all
  # prefixes, so a node reachable by several deeper stacks gets their combined
  # weight — exactly the width that node would occupy in the flame graph.
  -> .prefix_inclusive(map)
    incl = {}
    keys = map.keys()
    i = 0
    while i < keys.size()
      stack = keys[i]
      count = map[stack]
      frames = stack.split(";")
      prefix = ""
      fi = 0
      while fi < frames.size()
        if fi == 0
          prefix = frames[fi]
        else
          prefix = prefix + ";" + frames[fi]
        if incl.has_key?(prefix)
          incl[prefix] = incl[prefix] + count
        else
          incl[prefix] = count
        fi = fi + 1
      i = i + 1
    incl

  # ---- Threshold collapse ----

  # Fold every node below `min_pct_x10` (the minimum inclusive weight, in
  # tenths of a percent of the grand total, a node must have to survive) into
  # an "(other)" child of its last surviving ancestor. Returns folded text,
  # re-aggregated and sorted, with the grand total preserved exactly.
  #
  # A node survives iff `inclusive * 1000 >= total * min_pct_x10` (an exact
  # integer comparison — no division, no rounding). Walking each stack
  # root→leaf, the first node that fails truncates the stack: the surviving
  # prefix is kept and "(other)" is appended (or the stack becomes bare
  # "(other)" if even its root fails). A zero (or negative) threshold keeps
  # everything — the result is just the input, re-aggregated and sorted.
  -> .collapse(text, min_pct_x10)
    parsed = self.parse_folded(text)
    map = parsed[:map]
    total = parsed[:total]
    if total == 0
      return ""

    incl = self.prefix_inclusive(map)
    limit = total * min_pct_x10

    out = {}
    keys = map.keys()
    i = 0
    while i < keys.size()
      stack = keys[i]
      count = map[stack]
      frames = stack.split(";")

      kept = []
      prefix = ""
      folded_here = false
      fi = 0
      while fi < frames.size()
        if fi == 0
          prefix = frames[fi]
        else
          prefix = prefix + ";" + frames[fi]
        if incl[prefix] * 1000 < limit
          folded_here = true
          break
        kept.push(frames[fi])
        fi = fi + 1

      new_stack = ""
      if folded_here
        if kept.size() == 0
          new_stack = "(other)"
        else
          new_stack = kept.join(";") + ";(other)"
      else
        new_stack = kept.join(";")

      if out.has_key?(new_stack)
        out[new_stack] = out[new_stack] + count
      else
        out[new_stack] = count
      i = i + 1

    self.emit(out)

  # ---- Percentage parsing ----

  # Parse a percentage ("2", "0.5", "1.5") into tenths of a percent
  # (20, 5, 15) — the integer scale `.collapse` compares against, keeping all
  # threshold math in integers. A missing/empty/garbage value is 0 (keep
  # everything). Only the first fractional digit is significant (truncated,
  # not rounded), matching the one-decimal precision the rest of the bit
  # prints. The value is coerced through .to_s first because the arg parser
  # hands back an Integer for an all-digit option value ("20") but a String
  # for a fractional one ("0.5").
  -> .parse_pct_x10(s)
    if s == nil
      return 0
    t = s.to_s().strip()
    if t == ""
      return 0
    parts = t.split(".")
    whole = parts[0].to_i()
    frac = 0
    if parts.size() > 1
      fd = parts[1]
      if fd.size() > 0
        frac = fd.slice(0, 1).to_i()
    whole * 10 + frac

  # ---- Emit ----

  # Render a { stack => count } map back to folded text, one "stack count"
  # line per stack, sorted lexicographically by stack name for deterministic
  # output (matching FlameFilter.emit / FlameDiff).
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
