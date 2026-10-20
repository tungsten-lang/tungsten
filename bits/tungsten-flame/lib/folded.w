# folded.w — Shared folded-stack parsing, normalization, tree construction,
# and formatting utilities for tungsten-flame.
#
# Every module in tungsten-flame speaks the canonical folded-stack format
# ("root;mid;leaf <count>" per line). Centralizing parsing, emission,
# frame normalization, idle/infrastructure classification, call-tree
# construction, and fixed-point percentage formatting here keeps all
# views consistent and avoids duplicating helpers across worker modules.

in Tungsten:Flame

+ Folded

  # Read folded/profile text from `path`, or from standard input when
  # `path` is "-".
  -> .read_input(path)
    if path == "-"
      return read_file("/dev/stdin")
    read_file(path)

  # Parse folded text into { map: { stack => count }, total: N }.
  # Duplicate stacks are summed; lines with no positive count are ignored.
  # The trailing count is split with rindex(" ") so frame names containing
  # spaces (e.g. "block in Array#tally") survive intact.
  -> .parse(text)
    map = {}
    total = 0
    if text == nil
      return { map: map, total: 0 }
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

  # Render a { stack => count } map back to folded text, one "stack count"
  # line per stack, sorted lexicographically by stack name for deterministic
  # output.
  -> .emit(map)
    keys = map.keys().sort()
    out = []
    i = 0
    while i < keys.size()
      k = keys[i]
      out.push(k + " " + map[k].to_s())
      i = i + 1
    out.join("\n")

  # Normalize a decorated frame name: strip a trailing " + <decimal offset>"
  # and any "lib`" backtick prefix so decorated and undecorated appearances
  # of the same function merge into one symbol.
  -> .normalize_frame(name)
    frame = name
    plus_idx = frame.rindex(" + ")
    if plus_idx != nil
      rest = frame.slice(plus_idx + 3, frame.size())
      if rest.size() > 0 && rest.to_i().to_s() == rest
        frame = frame.slice(0, plus_idx)
    backtick = frame.rindex("`")
    if backtick != nil
      frame = frame.slice(backtick + 1, frame.size())
    frame

  # True when `name` (after stripping library prefix and offset) is a blocking
  # event-loop / poll syscall. Anchored to the normalized symbol name so user
  # functions containing "poll" or "kevent" as a substring (e.g. `poll_events`)
  # are never misclassified as idle.
  -> .idle_frame?(name)
    f = self.normalize_frame(name)
    f == "kevent" || f == "kevent64" || f == "kevent_id" || f == "kevent_qos" || f == "poll" || f == "__poll" || f == "epoll_wait" || f == "select" || f == "__select"

  # True when any frame in ";" -separated `stack` is an idle wait syscall.
  -> .idle_stack?(stack)
    frames = stack.split(";")
    i = 0
    while i < frames.size()
      if self.idle_frame?(frames[i])
        return true
      i = i + 1
    false

  # True when normalized leaf `name` is process/thread bootstrap scaffolding
  # (dyld, pthread/dispatch entry, fiber trampoline) rather than user work.
  # `main` is intentionally NOT treated as infrastructure because compiled
  # Tungsten top-level code lowers directly into `main`.
  -> .infra_leaf?(name)
    f = self.normalize_frame(name)
    infra_exact = ["start", "thread_start", "_ctx_start", "g_body_entry"]
    infra_prefix = ["dyld", "_dyld", "_pthread", "Thread_", "DispatchQueue"]
    j = 0
    while j < infra_exact.size()
      if name == infra_exact[j] || f == infra_exact[j]
        return true
      j = j + 1
    j = 0
    while j < infra_prefix.size()
      if name.starts_with?(infra_prefix[j]) || f.starts_with?(infra_prefix[j])
        return true
      j = j + 1
    false

  # Self (leaf-only) counts from a { stack => count } map. When `normalize`
  # is true, leaf names are normalized with .normalize_frame before tallying.
  -> .self_from_map(map, normalize)
    selfc = {}
    keys = map.keys()
    i = 0
    while i < keys.size()
      stack = keys[i]
      count = map[stack]
      frames = stack.split(";")
      leaf = frames.last()
      if normalize
        leaf = self.normalize_frame(leaf)
      if selfc.has_key?(leaf)
        selfc[leaf] = selfc[leaf] + count
      else
        selfc[leaf] = count
      i = i + 1
    selfc

  # Inclusive (total) per-frame counts from a { stack => count } map: every
  # distinct frame in a stack receives that stack's count once (recursion
  # within a single stack is not double-counted).
  -> .inclusive_from_map(map, normalize)
    incl = {}
    keys = map.keys()
    i = 0
    while i < keys.size()
      stack = keys[i]
      count = map[stack]
      frames = stack.split(";")
      seen = {}
      fi = 0
      while fi < frames.size()
        f = frames[fi]
        if normalize
          f = self.normalize_frame(f)
        if !seen.has_key?(f)
          seen[f] = true
          if incl.has_key?(f)
            incl[f] = incl[f] + count
          else
            incl[f] = count
        fi = fi + 1
      i = i + 1
    incl

  # ---- Merged call-tree construction (shared by FlameSvg & TraceEvent) ----

  # Parse folded text into a merged frame tree. Root is a virtual container
  # at depth -1 whose children are the depth-0 base frames; each node carries
  # `{ name:, count:, depth:, children:, by_name: }`.
  -> .build_tree(folded_text)
    root = { name: "root", count: 0, depth: -1, children: [], by_name: {} }
    if folded_text == nil
      return root
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
        child = { name: name, count: 0, depth: node[:depth] + 1, children: [], by_name: {} }
        node[:children].push(child)
        if node.has_key?(:by_name)
          node[:by_name][name] = child
      child[:count] = child[:count] + count
      node = child
      fi = fi + 1

  # O(1) child lookup via `node[:by_name]`, with linear fallback for any
  # caller-constructed node without `:by_name`.
  -> .find_child(node, name)
    if node.has_key?(:by_name)
      by_name = node[:by_name]
      if by_name.has_key?(name)
        return by_name[name]
      return nil
    kids = node[:children]
    i = 0
    while i < kids.size()
      if kids[i][:name] == name
        return kids[i]
      i = i + 1
    nil

  # Children sorted ascending by frame name for deterministic layout.
  -> .sort_children(kids)
    kids.sort_by -> (c) c[:name]

  # ---- Formatting & escaping helpers ----

  # Percentage with one decimal via integer math ("33.3").
  -> .fmt_pct(n, total)
    if total == 0
      return "0.0"
    pct_x10 = n * 1000 / total
    whole = pct_x10 / 10
    frac = pct_x10 - whole * 10
    whole.to_s() + "." + frac.to_s()

  # Percentage with one decimal, left-padded to 5 chars (" 33.3").
  -> .fmt_pct_padded(n, total)
    self.pad_left(self.fmt_pct(n, total), 5)

  -> .pad_left(s, width)
    out = s.to_s()
    while out.size() < width
      out = " " + out
    out

  -> .pad_right(s, width)
    out = s.to_s()
    while out.size() < width
      out = out + " "
    out

  # Escape characters required inside JSON string literals.
  -> .json_escape(s)
    s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t")

  # True when `s` is a non-empty run of ASCII decimal digits.
  -> .all_digits?(s)
    if s.size() == 0
      return false
    i = 0
    while i < s.size()
      c = s.slice(i, 1)
      if c < "0" || c > "9"
        return false
      i = i + 1
    true
