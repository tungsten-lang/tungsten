# flame_threshold.w — Minimum-width threshold pruning: fold the long tail
# of tiny frames into a single "(other)" node.

use folded

in Tungsten:Flame

+ FlameThreshold

  # ---- Parsing ----

  -> .parse_folded(text)
    Tungsten:Flame:Folded.parse(text)

  # ---- Inclusive node weights ----

  # Inclusive weight of every call-tree node, keyed by its full root→node
  # path string ("main", "main;a", "main;a;b", ...).
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

  # Fold every node below `min_pct_x10` (in tenths of a percent of the grand
  # total) into an "(other)" child of its last surviving ancestor.
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

  # Parse a percentage ("2", "0.5", "1.5") into tenths of a percent (20, 5, 15).
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

  -> .emit(map)
    Tungsten:Flame:Folded.emit(map)
