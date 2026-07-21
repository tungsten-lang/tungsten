# flame_filter.w — Stack filtering: reshape a folded profile before viewing.
#
# Every other view in this bit consumes folded stacks whole. But the first
# thing you do with a real profile is narrow it: "show me only the work under
# parse", "hide the GC / idle noise", "zoom into the fib subtree". Interactive
# flame graphs do this with click-to-zoom; the classic offline workflow is
# `grep foo stacks.folded | flamegraph.pl`. This module is that operation as a
# first-class, testable transform.
#
# It is a pure folded-text → folded-text filter (the same "root;mid;leaf
# <count>" text every module here speaks), so its output pipes straight into
# any other view — SVG (flame_svg), the flat profile (--hot), speedscope
# export, or a diff. Three complementary operations, all matching on a frame
# SUBSTRING (so "kevent" matches "libsystem_kernel.dylib`kevent + 8"):
#
#   - .keep(text, pat)   include: keep whole stacks that pass through a frame
#                        matching `pat` (the `grep foo | flamegraph.pl` filter).
#   - .drop(text, pat)   exclude: drop whole stacks that touch `pat` (mute GC,
#                        idle, a noisy library) — the inverse of .keep.
#   - .focus(text, pat)  zoom: keep matching stacks AND trim each so the first
#                        matching frame becomes the new root, collapsing the
#                        callers above it. This is click-to-zoom: it re-roots
#                        the graph at `pat` and re-aggregates the resulting
#                        subtree stacks. Plain `grep` cannot do this — it keeps
#                        the callers, so `pat` never becomes 100%.
#
# .apply chains them (subtree-or-keep, then drop) for the CLI. Output is
# re-aggregated (trimmed duplicates summed) and sorted by stack name, matching
# PerfScript.collapse / FlameDiff for deterministic, golden-file output.
#
# CLI: `flame --grep PAT FILE.folded`, `--prune PAT`, `--subtree PAT` — a
# pure-text mode like --diff / --hot (no compile, no profiling); result to
# stdout, or to -o.

in Tungsten:Flame

+ FlameFilter

  # ---- Parsing ----

  # Parse folded text into { map: { stack => count }, total: N }. Duplicate
  # stacks are summed; lines with no positive count are ignored — matching
  # FlameDiff.parse_folded / HotFrames.parse_folded so every module agrees on
  # what a sample is. Count split with rindex(" ") so frame names containing
  # spaces (e.g. "block in Array#tally") survive.
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

  # ---- Matching ----

  # True when any frame of `stack` (split on ";") contains `pat` as a
  # substring. An empty pattern matches every stack (include? "" is true).
  -> .stack_matches(stack, pat)
    frames = stack.split(";")
    i = 0
    while i < frames.size()
      if frames[i].include?(pat)
        return true
      i = i + 1
    false

  # Trim `stack` to the subtree rooted at its FIRST frame containing `pat`:
  # returns that frame and everything below it, re-joined with ";". Returns nil
  # when no frame matches (the stack is not part of the focused subtree).
  -> .trim_to(stack, pat)
    frames = stack.split(";")
    i = 0
    while i < frames.size()
      if frames[i].include?(pat)
        kept = []
        j = i
        while j < frames.size()
          kept.push(frames[j])
          j = j + 1
        return kept.join(";")
      i = i + 1
    nil

  # ---- Operations ----

  # Include: keep only stacks that pass through a frame matching `pat`. Whole
  # stacks are retained (callers preserved); counts unchanged. Re-emitted
  # aggregated + sorted.
  -> .keep(text, pat)
    map = self.parse_folded(text)[:map]
    out = {}
    keys = map.keys()
    i = 0
    while i < keys.size()
      stack = keys[i]
      if self.stack_matches(stack, pat)
        out[stack] = map[stack]
      i = i + 1
    self.emit(out)

  # Exclude: keep only stacks that do NOT touch `pat` anywhere. The inverse of
  # .keep — mutes a noisy library, GC, or idle frames.
  -> .drop(text, pat)
    map = self.parse_folded(text)[:map]
    out = {}
    keys = map.keys()
    i = 0
    while i < keys.size()
      stack = keys[i]
      if !self.stack_matches(stack, pat)
        out[stack] = map[stack]
      i = i + 1
    self.emit(out)

  # Zoom: keep matching stacks and re-root each at the first frame matching
  # `pat`, dropping the callers above it. Distinct trimmed stacks that collapse
  # onto the same subtree are summed, so `pat` becomes the graph's 100% root.
  -> .focus(text, pat)
    map = self.parse_folded(text)[:map]
    out = {}
    keys = map.keys()
    i = 0
    while i < keys.size()
      stack = keys[i]
      trimmed = self.trim_to(stack, pat)
      if trimmed != nil
        if out.has_key?(trimmed)
          out[trimmed] = out[trimmed] + map[stack]
        else
          out[trimmed] = map[stack]
      i = i + 1
    self.emit(out)

  # CLI pipeline: apply a subtree-zoom OR an include, then an exclude. Each
  # argument is a pattern; "" means "skip this step". `subtree` wins over
  # `grep` when both are given (zoom is the more specific include). The result
  # is folded text, so the steps compose (drop re-parses focus's output).
  -> .apply(text, grep, prune, subtree)
    result = text
    if subtree != ""
      result = self.focus(result, subtree)
    elsif grep != ""
      result = self.keep(result, grep)
    if prune != ""
      result = self.drop(result, prune)
    result

  # Number of stacks (non-empty folded lines) in a folded string — for the
  # CLI's "kept N stacks" note. Empty text is 0 stacks.
  -> .stack_count(text)
    n = 0
    lines = text.split("\n")
    i = 0
    while i < lines.size()
      if lines[i].strip().size() > 0
        n = n + 1
      i = i + 1
    n

  # ---- Emit ----

  # Render a { stack => count } map back to folded text, one "stack count" line
  # per stack, sorted lexicographically by stack name for deterministic output.
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
