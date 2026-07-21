# trace_event.w — Export folded stacks as a chrome://tracing / Perfetto
# Trace Event Format profile.
#
# This bit already emits two viewer targets: the self-contained interactive
# SVG (flame_svg.w) and a speedscope.app "sampled" profile (speedscope.w).
# Neither reaches the trace-viewer ecosystem: Google's Perfetto
# (https://ui.perfetto.dev) and the chrome://tracing view built into every
# Chromium browser. Both read the *Trace Event Format* — a JSON document of
# timeline slices — and give a flame-CHART, track-based timeline with SQL
# query (Perfetto) and marquee zoom, all with zero install. This module is
# that missing export.
#
# Speedscope's format is a flat list of samples (frame-index arrays +
# parallel weights); the SVG is a static icicle picture. The Trace Event
# Format is neither: it is a *timeline* of nested duration slices, so this
# module reconstructs one. Folded text has lost real time-order, so we
# synthesize a deterministic timeline — merge the stacks into a call tree
# (shared prefixes fuse, exactly like the SVG), then walk it depth-first
# laying every node out as a "complete" ("X") slice at
# [offset, offset + inclusive-count) on a single synthetic track. A child's
# span nests inside its parent's by time containment (chrome/Perfetto's
# stacking rule), and the strip of a parent past its children shows as self
# time — the same flame-graph semantics flame_svg.w draws, expressed as a
# trace. Sibling roots lay out consecutively; no synthetic "all" root is
# inserted (faithful to flamegraph.pl, matching flame_svg.w).
#
#   {
#     "displayTimeUnit": "ns",
#     "traceEvents": [
#       {"name":"process_name","ph":"M","pid":1,"args":{"name":"demo"}},
#       {"name":"thread_name","ph":"M","pid":1,"tid":1,"args":{"name":"samples"}},
#       {"name":"main","ph":"X","ts":0,"dur":18,"pid":1,"tid":1},
#       {"name":"a","ph":"X","ts":0,"dur":15,"pid":1,"tid":1},
#       ...
#     ]
#   }
#
# Sample counts map 1:1 onto ts/dur units; only relative widths matter, so
# the picture is faithful whatever the unit. Stacks are sorted and children
# emitted in name order for deterministic, golden-file-friendly output — the
# same discipline every other module in this bit follows. Duplicate stacks
# sum; lines with no positive count are ignored (matching FlameSvg.build_tree
# and Speedscope.dedupe_counts). Empty input yields a valid, slice-less trace.
#
# Pure text -> JSON: no profiling, no atos, no external assets — fully
# unit-testable, and complementary to flame_svg.w and speedscope.w (a third
# viewer target for the same folded data), not a replacement for either.
#
# CLI: `flame --trace-event FILE.folded [MORE...]` — emits the JSON to -o (or
# stdout). A pure folded-text mode like --hot / --collapse-sample; several
# files concatenate and their stacks sum, aggregating N runs into one trace.

in Tungsten:Flame

+ TraceEvent

  # ---- Public entry point ----

  # Folded-stack text -> a complete Trace Event Format JSON document
  # (string). `process_name` labels the process track in the viewer. Empty /
  # count-less input yields a valid trace with the metadata events but no
  # slices (rather than crashing).
  -> .export(folded_text, process_name)
    root = self.build_tree(folded_text)
    events = []
    events.push(self.process_meta(process_name))
    events.push(self.thread_meta("samples"))
    self.emit_children(root, 0, events)
    out = []
    out.push("{\"displayTimeUnit\":\"ns\",\"traceEvents\":\[")
    out.push(events.join(","))
    out.push("\]}")
    out.join("")

  # ---- Timeline synthesis ----

  # Emit every child of `node` as a slice, laid out left-to-right starting at
  # `offset` (sample-space). Each child spans [cur, cur + its inclusive
  # count); its own subtree is emitted nested within that span before the
  # cursor advances past it. Recurses depth-first; appends to `events`.
  -> .emit_children(node, offset, events)
    kids = self.sort_children(node[:children])
    cur = offset
    i = 0
    while i < kids.size()
      child = kids[i]
      events.push(self.slice_event(child[:name], cur, child[:count]))
      self.emit_children(child, cur, events)
      cur = cur + child[:count]
      i = i + 1

  # One "complete" (ph "X") duration slice: name, start ts, duration dur, on
  # the single synthetic process/thread track (pid 1, tid 1). Nesting is by
  # time containment, so no explicit depth is needed.
  -> .slice_event(name, ts, dur)
    "{\"name\":\"" + self.json_escape(name) + "\",\"ph\":\"X\",\"ts\":" + ts.to_s() + ",\"dur\":" + dur.to_s() + ",\"pid\":1,\"tid\":1}"

  # Process-name metadata (ph "M") — labels the track in the viewer.
  -> .process_meta(name)
    "{\"name\":\"process_name\",\"ph\":\"M\",\"pid\":1,\"args\":{\"name\":\"" + self.json_escape(name) + "\"}}"

  # Thread-name metadata (ph "M") for the single synthetic track.
  -> .thread_meta(name)
    "{\"name\":\"thread_name\",\"ph\":\"M\",\"pid\":1,\"tid\":1,\"args\":{\"name\":\"" + self.json_escape(name) + "\"}}"

  # ---- Tree construction ----

  # Parse folded text into a merged frame tree. Root is a virtual container
  # whose children are the real base frames; each node's `count` is its
  # inclusive sample total. Duplicate stacks sum; lines with no positive
  # count are ignored (matching FlameSvg.build_tree).
  -> .build_tree(folded_text)
    root = { name: "root", count: 0, children: [] }
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
            self.insert_stack(root, stack.split(";"), count)
      i = i + 1
    root

  -> .insert_stack(root, frames, count)
    root[:count] = root[:count] + count
    node = root
    fi = 0
    while fi < frames.size()
      name = frames[fi]
      child = self.find_child(node, name)
      if child == nil
        child = { name: name, count: 0, children: [] }
        node[:children].push(child)
      child[:count] = child[:count] + count
      node = child
      fi = fi + 1

  -> .find_child(node, name)
    kids = node[:children]
    i = 0
    while i < kids.size()
      if kids[i][:name] == name
        return kids[i]
      i = i + 1
    nil

  # ---- Helpers ----

  # Children sorted by name (deterministic, golden-file-friendly output),
  # matching FlameSvg.sort_children so both views merge and order alike.
  -> .sort_children(kids)
    arr = []
    i = 0
    while i < kids.size()
      arr.push(kids[i])
      i = i + 1
    j = 1
    while j < arr.size()
      key = arr[j]
      k = j - 1
      while k >= 0 && arr[k][:name] > key[:name]
        arr[k + 1] = arr[k]
        k = k - 1
      arr[k + 1] = key
      j = j + 1
    arr

  # Escape the two characters JSON string literals must escape: the
  # backslash (first, so its escapes aren't re-escaped) and the double
  # quote. Frame names are single-line, so no control chars appear. Matches
  # Speedscope.json_escape.
  -> .json_escape(s)
    s.replace("\\", "\\\\").replace("\"", "\\\"")
