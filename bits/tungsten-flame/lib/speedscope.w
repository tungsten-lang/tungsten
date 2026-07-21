# speedscope.w — Export folded stacks as a speedscope.app profile.
#
# The interactive SVG (flame_svg.w) is self-contained but static: one
# icicle picture, click-to-zoom, nothing more. speedscope.app is the
# industry-standard *interactive* profile viewer, and it reads a simple
# JSON document — drop the file on https://www.speedscope.app and you get
# the Time-Order, Left-Heavy, and Sandwich views (per-frame self/total
# rollups, caller/callee flame charts) for free, in any browser.
#
# This module turns the same folded-stack text every other module in this
# bit speaks ("root;mid;leaf <count>" per line) into speedscope's
# "sampled" profile format:
#
#   {
#     "$schema": "https://www.speedscope.app/file-format-schema.json",
#     "shared": { "frames": [ {"name": "main"}, {"name": "a"}, ... ] },
#     "profiles": [ {
#       "type": "sampled", "name": ..., "unit": "none",
#       "startValue": 0, "endValue": <total weight>,
#       "samples": [ [0,1,2], [0,1,3], ... ],   # frame indices, root→leaf
#       "weights": [ 10, 5, ... ]               # parallel to samples
#     } ]
#   }
#
# A "sample" is one distinct stack; its "weight" is the summed count of
# that stack. Because folded text has already lost real time-order,
# stacks are deduped (weights summed) and emitted sorted by name — the
# same deterministic, golden-file-friendly discipline the rest of the bit
# follows. The frame table lists each unique frame once (first-seen order
# across the sorted stacks); every sample references frames by index.
#
# Pure text→JSON: no profiling, no atos, no external assets — fully
# unit-testable, and complementary to flame_svg.w (a different output
# target for the same folded data), not a replacement for it.

in Tungsten:Flame

+ Speedscope

  # ---- Public entry point ----

  # Folded-stack text → a complete speedscope "sampled" profile JSON
  # document (string). `profile_name` labels the profile in the viewer's
  # tab. Empty / count-less input yields a valid, empty profile (endValue
  # 0, no frames, no samples) rather than crashing.
  -> .export(folded_text, profile_name)
    counts = self.dedupe_counts(folded_text)
    stacks = self.sort_strings(counts.keys())

    # Frame table: each unique frame once, indexed in first-seen order
    # across the sorted stacks (deterministic).
    frame_names = []
    frame_index = {}
    si = 0
    while si < stacks.size()
      frames = stacks[si].split(";")
      fi = 0
      while fi < frames.size()
        f = frames[fi]
        if !frame_index.has_key?(f)
          frame_index[f] = frame_names.size()
          frame_names.push(f)
        fi = fi + 1
      si = si + 1

    # Samples (index arrays, root→leaf) + parallel weights + total.
    samples = []
    weights = []
    total = 0
    si = 0
    while si < stacks.size()
      stack = stacks[si]
      frames = stack.split(";")
      idxs = []
      fi = 0
      while fi < frames.size()
        idxs.push(frame_index[frames[fi]].to_s())
        fi = fi + 1
      samples.push("\[" + idxs.join(",") + "\]")
      weights.push(counts[stack].to_s())
      total = total + counts[stack]
      si = si + 1

    # Frame table JSON objects.
    frames_json = []
    fi = 0
    while fi < frame_names.size()
      frames_json.push("{\"name\":\"" + self.json_escape(frame_names[fi]) + "\"}")
      fi = fi + 1

    out = []
    out.push("{")
    out.push("\"$schema\":\"https://www.speedscope.app/file-format-schema.json\",")
    out.push("\"exporter\":\"tungsten-flame\",")
    out.push("\"name\":\"" + self.json_escape(profile_name) + "\",")
    out.push("\"activeProfileIndex\":0,")
    out.push("\"shared\":{\"frames\":\[" + frames_json.join(",") + "\]},")
    out.push("\"profiles\":\[{")
    out.push("\"type\":\"sampled\",")
    out.push("\"name\":\"" + self.json_escape(profile_name) + "\",")
    out.push("\"unit\":\"none\",")
    out.push("\"startValue\":0,")
    out.push("\"endValue\":" + total.to_s() + ",")
    out.push("\"samples\":\[" + samples.join(",") + "\],")
    out.push("\"weights\":\[" + weights.join(",") + "\]")
    out.push("}\]}")
    out.join("")

  # ---- Parsing ----

  # Parse folded text into { stack_string => summed_count }. Duplicate
  # stacks are summed; lines with no positive count are ignored (matching
  # FlameSvg.build_tree and FlameDiff.parse_folded, so all three agree on
  # what a sample is). The trailing count is split off with rindex(" "), so
  # frame names containing spaces (e.g. "block in Array#tally") survive.
  -> .dedupe_counts(folded_text)
    counts = {}
    lines = folded_text.split("\n")
    i = 0
    while i < lines.size()
      line = lines[i].strip()
      if line.size() > 0
        sp = line.rindex(" ")
        if sp != nil
          stack = line.slice(0, sp)
          count = line.slice(sp + 1, line.size()).to_i()
          if count > 0
            if counts.has_key?(stack)
              counts[stack] = counts[stack] + count
            else
              counts[stack] = count
      i = i + 1
    counts

  # ---- Helpers ----

  # Escape the two characters JSON string literals must escape: the
  # backslash (first, so its escapes aren't re-escaped) and the double
  # quote. Frame names are single-line, so no control chars appear.
  -> .json_escape(s)
    s.replace("\\", "\\\\").replace("\"", "\\\"")

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
