# sidemap.w — Map deduped `__wy_<hash>` symbols back to real names.
#
# The compiler dedupes identical function bodies behind wyhash64 symbols
# (`__wy_` + 8 hex chars) and writes a `.sidemap` JSON next to every
# binary it builds (`out_path + ".sidemap"`), mapping each hash back to
# the original definitions. One hash per line inside "hashes":
#
#   "fd278cb267950fc0": {"symbol": "__wy_fd278cb2", "originals":
#     \[{"symbol":"__w_fib","class":null,"method":"fib","kind":"method_def",...}\]},
#
# The top-level "symbol" key is written with a space after the colon,
# the per-original keys without — parse() leans on that to split out
# originals without needing a full JSON parser.
#
# Flame compiles the profiling target itself (Builder.compile), so it
# knows exactly where the target's sidemap lives; flame.w loads it and
# rewrites every metric's folded text before display/SVG export.

in Tungsten:Flame

+ Sidemap

  # Load `path` → { "__wy_xxxxxxxx" => display_name }. Missing or
  # unreadable file → empty dict (callers degrade to raw hashes).
  -> .load(path)
    text = read_file(path)
    if text == nil
      return {}
    self.parse(text)

  -> .parse(text)
    result = {}
    lines = text.split("\n")
    i = 0
    while i < lines.size()
      line = lines[i]
      key_pos = line.index("\"symbol\": \"")
      if key_pos != nil
        rest = line.slice(key_pos + 11, line.size())
        q = rest.index("\"")
        if q != nil
          wy = rest.slice(0, q)
          name = self.display_name(line)
          if name != nil
            result[wy] = name
      i = i + 1
    result

  # Human name for one sidemap hash line. Distinct original names are
  # collapsed to the first plus a "(+N)" alias count — deduped bodies
  # (e.g. Array/Hash/Range sharing an Enumerable method) are one
  # machine function, so one profile row is the honest rendering.
  -> .display_name(line)
    pieces = line.split("{\"symbol\":\"")
    if pieces.size() < 2
      return nil
    names = []
    pi = 1
    while pi < pieces.size()
      n = self.original_name(pieces[pi])
      if n != nil
        dup = false
        ni = 0
        while ni < names.size()
          if names[ni] == n
            dup = true
          ni = ni + 1
        if !dup
          names.push(n)
      pi = pi + 1
    if names.size() == 0
      return nil
    if names.size() == 1
      return names[0]
    names[0] + " (+" + (names.size() - 1).to_s() + ")"

  # One original record → display name:
  #   method/method_def  Class#method   (bare `method` when class is null)
  #   static_method      Class.method
  #   block              block in Class#method
  -> .original_name(piece)
    method = self.attr(piece, "method")
    if method == nil
      return nil
    cls = self.attr(piece, "class")
    kind = self.attr(piece, "kind")
    base = method
    if cls != nil && cls != ""
      sep = "#"
      if kind == "static_method"
        sep = "."
      base = cls + sep + method
    if kind == "block"
      base = "block in " + base
    base

  # Value of `"key":"value"` in `piece`, or nil when the key is absent
  # or its value is JSON null (written unquoted, so the pattern misses).
  -> .attr(piece, key)
    pat = "\"" + key + "\":\""
    pos = piece.index(pat)
    if pos == nil
      return nil
    rest = piece.slice(pos + pat.size(), piece.size())
    q = rest.index("\"")
    if q == nil
      return nil
    rest.slice(0, q)

  # Rewrite frames of a folded-stacks text ("f1;f2;leaf count" lines)
  # through `map`. Unmapped frames and counts pass through untouched,
  # line order is preserved.
  -> .rewrite_folded(folded_text, map)
    if map.keys().size() == 0
      return folded_text
    lines = folded_text.split("\n")
    out = []
    i = 0
    while i < lines.size()
      line = lines[i]
      if line.size() == 0
        out.push(line)
      else
        sp = line.rindex(" ")
        stack = line
        count = nil
        if sp != nil
          stack = line.slice(0, sp)
          count = line.slice(sp + 1, line.size())
        frames = stack.split(";")
        mapped = []
        fi = 0
        while fi < frames.size()
          f = frames[fi]
          if map.has_key?(f)
            mapped.push(map[f])
          else
            mapped.push(f)
          fi = fi + 1
        rl = mapped.join(";")
        if count != nil
          rl = rl + " " + count
        out.push(rl)
      i = i + 1
    out.join("\n")
