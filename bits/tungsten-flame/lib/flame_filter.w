# flame_filter.w — Stack filtering: reshape a folded profile before viewing.

use folded

in Tungsten:Flame

+ FlameFilter

  # ---- Parsing ----

  -> .parse_folded(text)
    Tungsten:Flame:Folded.parse(text)

  # ---- Matching ----

  # True when any frame of `stack` (split on ";") contains `pat` as a
  # substring. An empty pattern matches every stack.
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
  # when no frame matches.
  -> .trim_to(stack, pat)
    frames = stack.split(";")
    i = 0
    while i < frames.size()
      if frames[i].include?(pat)
        return frames.drop(i).join(";")
      i = i + 1
    nil

  # ---- Operations ----

  # Include: keep only stacks that pass through a frame matching `pat`.
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

  # Exclude: keep only stacks that do NOT touch `pat` anywhere.
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
  # `pat`, dropping the callers above it.
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

  # CLI pipeline: apply a subtree-zoom OR an include, then an exclude.
  -> .apply(text, grep, prune, subtree)
    result = text
    if subtree != ""
      result = self.focus(result, subtree)
    elsif grep != ""
      result = self.keep(result, grep)
    if prune != ""
      result = self.drop(result, prune)
    result

  # Number of stacks (non-empty folded lines) in a folded string.
  -> .stack_count(text)
    text.split("\n").select(-> (ln) ln.strip().size() > 0).size()

  # ---- Emit ----

  -> .emit(map)
    Tungsten:Flame:Folded.emit(map)
