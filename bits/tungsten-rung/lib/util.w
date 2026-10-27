# rung — small helpers: paths, files, shell quoting, text and time.
#
# Every helper is prefixed `rung_` because bit functions share one global
# namespace with core and the other bits a program loads.

RUNG_VERSION = "0.1.0"

# ---- text ---------------------------------------------------------------------------

# Literal (non-pattern) replacement of every occurrence of `from`.
-> rung_replace(s, from, to)
  return s if from == ""
  out = ""
  i = 0
  while true
    j = s.index(from, i)
    if j == nil
      out = out + s.slice(i, s.size - i)
      return out
    out = out + s.slice(i, j - i) + to
    i = j + from.size

-> rung_blank?(s)
  s == nil || s.to_s.strip == ""

# Lines of a text without the phantom empty line a trailing newline leaves.
-> rung_lines(text)
  return [] if text == nil || text == ""
  ls = text.split("\n")
  if ls.size > 0 && ls[ls.size - 1] == ""
    ls.pop
  out = []
  ls.each -> (l)
    if l.ends_with?("\r")
      out.push(l.slice(0, l.size - 1))
    else
      out.push(l)
  out

-> rung_pad(s, width)
  t = s.to_s
  while t.size < width
    t = t + " "
  t

-> rung_two(n)
  n.to_s.rjust(2, "0")

# "12.3 s" from milliseconds.
-> rung_secs(ms)
  return "0 s" if ms == nil
  whole = ms / 1000
  tenth = (ms % 1000) / 100
  if whole >= 100
    return whole.to_s + " s"
  whole.to_s + "." + tenth.to_s + " s"

-> rung_first_line(s)
  return "" if s == nil
  ls = rung_lines(s.to_s.strip)
  return "" if ls.size == 0
  ls[0]

# A Markdown table cell: one line, pipes escaped.
-> rung_cell(s)
  t = rung_replace(s.to_s, "\n", " ")
  rung_replace(t, "|", "\\|")

# File-name-safe label: letters, digits and . _ + - only.
-> rung_slug(s)
  out = ""
  i = 0
  while i < s.size
    c = s.slice(i, 1)
    b = s.byte_at(i)
    if (b >= 48 && b <= 57) || (b >= 65 && b <= 90) || (b >= 97 && b <= 122) || c == "." || c == "_" || c == "+" || c == "-"
      out = out + c
    else
      out = out + "-"
    i += 1
  out

-> rung_contains?(arr, x)
  i = 0
  while i < arr.size
    return true if arr[i] == x
    i += 1
  false

-> rung_uniq_push(arr, x)
  arr.push(x) unless rung_contains?(arr, x)
  arr

# Sorted copy of an array of strings (insertion sort keeps it engine-neutral).
-> rung_sorted(arr)
  out = []
  arr.each -> (x)
    out.push(x)
  i = 1
  while i < out.size
    v = out[i]
    j = i - 1
    while j >= 0 && out[j] > v
      out[j + 1] = out[j]
      j -= 1
    out[j + 1] = v
    i += 1
  out

# ---- shell --------------------------------------------------------------------------

-> rung_shq(s)
  "'" + rung_replace(s.to_s, "'", "'\\''") + "'"

# ---- paths --------------------------------------------------------------------------

-> rung_home
  h = Env.get("HOME")
  rung_blank?(h) ? "/" : h

-> rung_expand_home(p)
  return rung_home if p == "~"
  return rung_home + p.slice(1, p.size - 1) if p.starts_with?("~/")
  p

# Absolute, normalized path (. and .. folded) without touching the disk.
-> rung_abs(p, base = nil)
  q = rung_expand_home(p.to_s)
  if !q.starts_with?("/")
    b = base == nil ? Dir.pwd : base
    q = b + "/" + q
  parts = []
  q.split("/").each -> (seg)
    if seg == "" || seg == "."
      0
    elsif seg == ".."
      parts.pop if parts.size > 0
    else
      parts.push(seg)
  "/" + parts.join("/")

-> rung_basename(p)
  q = p
  while q.size > 1 && q.ends_with?("/")
    q = q.slice(0, q.size - 1)
  i = q.rindex("/")
  return q if i == nil
  q.slice(i + 1, q.size - i - 1)

-> rung_dirname(p)
  q = p
  while q.size > 1 && q.ends_with?("/")
    q = q.slice(0, q.size - 1)
  i = q.rindex("/")
  return "." if i == nil
  return "/" if i == 0
  q.slice(0, i)

-> rung_stem(p)
  b = rung_basename(p)
  i = b.rindex(".")
  return b if i == nil || i == 0
  b.slice(0, i)

-> rung_join(a, b)
  return b if b.starts_with?("/")
  return a + b if a.ends_with?("/")
  a + "/" + b

# `path` relative to `dir` when it lies inside it, else nil.
-> rung_relative(path, dir)
  d = dir.ends_with?("/") ? dir : dir + "/"
  return nil unless path.starts_with?(d)
  path.slice(d.size, path.size - d.size)

# ---- files --------------------------------------------------------------------------

-> rung_exists?(p)
  File.exist?(p)

-> rung_dir?(p)
  File.directory?(p)

-> rung_file?(p)
  File.file?(p)

-> rung_read(p)
  return nil unless File.file?(p)
  File.read(p)

-> rung_mkdir(p)
  File.mkdir_p(p) unless File.directory?(p)
  p

# Write through a sibling temp file so a crash never leaves half a file
# behind (resume reads these).
-> rung_write(p, text)
  rung_mkdir(rung_dirname(p))
  File.atomic_write(p, text)
  p

-> rung_append(p, text)
  old = rung_read(p)
  old = "" if old == nil
  rung_write(p, old + text)

-> rung_file_size(p)
  st = File.stat(p)
  st == nil ? 0 : st.size

# Byte copy, then read-only (0444): models get copies, never originals.
-> rung_copy_ro(src, dst)
  rung_mkdir(rung_dirname(dst))
  File.write_bytes(dst, File.read_bytes(src))
  File.chmod(dst, 0o444)
  dst

-> rung_rm_rf(p)
  return true unless File.exist?(p) || File.symlink?(p)
  Process.spawn(["/bin/rm", "-rf", p]).wait == 0

# Children of a directory, sorted, without . and ..
-> rung_children(dir)
  out = []
  File.read_dir(dir).each -> (e)
    out.push(e) unless e == "." || e == ".."
  rung_sorted(out)

# Every regular file under dir (relative paths, sorted), skipping dot
# entries and symlinked directories.
-> rung_walk_files(dir, prefix = "")
  out = []
  rung_children(dir).each -> (e)
    if !e.starts_with?(".")
      full = dir + "/" + e
      rel = prefix == "" ? e : prefix + "/" + e
      lst = File.lstat(full)
      if lst != nil && lst.symlink? && File.directory?(full)
        0
      elsif File.directory?(full)
        rung_walk_files(full, rel).each -> (x)
          out.push(x)
      elsif File.file?(full)
        out.push(rel)
  out

# ---- time ---------------------------------------------------------------------------

-> rung_ms
  ccall("__w_clock_ms")

# Typed: __w_sleep_ms takes a raw i64 (an untyped, boxed argument would
# arrive as a negative number and not sleep at all).
-> rung_sleep_ms(ms) (i64)
  ccall("__w_sleep_ms", ms)

# Local wall-clock stamps (for names and reports, never for durations).
# Fixed command strings: nothing from a prompt or a model reaches a shell here.
-> rung_timestamp
  OS.capture("/bin/date '+%Y-%m-%d %H:%M:%S %z'").strip

-> rung_stamp_compact
  OS.capture("/bin/date '+%Y%m%d-%H%M%S'").strip

# ---- JSON ---------------------------------------------------------------------------

-> rung_json_read(p)
  t = rung_read(p)
  return nil if rung_blank?(t)
  begin
    return JSON.parse(t)
  rescue e
    return nil
  nil

-> rung_json_write(p, value)
  rung_write(p, JSON.encode(value) + "\n")

# A line on stderr.
-> rung_warn(msg)
  ccall("w_eputs", msg)
  nil
