# rung — staging: the files a prompt names, copied read-only for each model.
#
# Patterns are relative to the prompt file's directory (or absolute, or
# ~/...). `*` and `?` match within one path segment, `**` matches any number
# of directories, and a directory stands for every file under it. Dot files
# and dot directories are skipped unless the pattern names them.
#
# rung copies the matches once into RUN/stage/ (so a resumed run sees the
# same bytes), then into each call's own work dir, every copy mode 0444.

-> rung_wild?(s)
  s.index("*") != nil || s.index("?") != nil

# fnmatch for one segment: * and ?.
-> rung_fnmatch(pat, name)
  rung_fnmatch_at(pat, 0, name, 0)

-> rung_fnmatch_at(pat, pi, name, ni)
  while pi < pat.size
    c = pat.slice(pi, 1)
    if c == "*"
      while pi < pat.size && pat.slice(pi, 1) == "*"
        pi += 1
      return true if pi == pat.size
      k = ni
      while k <= name.size
        return true if rung_fnmatch_at(pat, pi, name, k)
        k += 1
      return false
    return false if ni >= name.size
    if c != "?" && c != name.slice(ni, 1)
      return false
    pi += 1
    ni += 1
  ni == name.size

# Absolute file paths matched by one pattern, sorted, with the anchor
# directory their staged names are relative to.
-> rung_glob(base, pattern)
  pat = rung_expand_home(pattern.strip)
  abs = pat.starts_with?("/") ? pat : base + "/" + pat
  segs = []
  abs.split("/").each -> (s)
    segs.push(s) unless s == "" || s == "."
  # literal prefix: the segments before the first wildcard
  lit = []
  i = 0
  while i < segs.size && !rung_wild?(segs[i])
    lit.push(segs[i])
    i += 1
  root = rung_abs("/" + lit.join("/"))
  found = []
  if i == segs.size
    # no wildcard: a file or a directory
    if File.file?(root)
      found.push(root)
    elsif File.directory?(root)
      rung_walk_files(root).each -> (r)
        found.push(root + "/" + r)
  else
    rung_glob_walk(root, segs, i, found)
  files = rung_sorted(found)
  anchor = base
  inside = true
  files.each -> (f)
    inside = false if rung_relative(f, base) == nil
  if !inside
    if i < segs.size
      anchor = root
    elsif File.directory?(root)
      anchor = rung_dirname(root)
    else
      anchor = rung_dirname(root)
  {"files" => files, "anchor" => anchor}

-> rung_glob_walk(path, segs, i, out)
  if i == segs.size
    if File.file?(path)
      out.push(path)
    elsif File.directory?(path)
      rung_walk_files(path).each -> (r)
        out.push(path + "/" + r)
    return out
  return out unless File.directory?(path)
  seg = segs[i]
  if seg == "**"
    rung_glob_walk(path, segs, i + 1, out)
    rung_children(path).each -> (e)
      full = path + "/" + e
      lst = File.lstat(full)
      symdir = lst != nil && lst.symlink?
      if !e.starts_with?(".") && File.directory?(full) && !symdir
        rung_glob_walk(full, segs, i, out)
    return out
  if rung_wild?(seg)
    rung_children(path).each -> (e)
      if (!e.starts_with?(".") || seg.starts_with?(".")) && rung_fnmatch(seg, e)
        rung_glob_walk(path + "/" + e, segs, i + 1, out)
    return out
  rung_glob_walk(path + "/" + seg, segs, i + 1, out)

# Resolve every pattern: [{"src" => abs, "rel" => staged name, "bytes" => n}].
# Raises when a pattern matches nothing, two files claim one staged name, or
# the set exceeds the limits.
-> rung_resolve_stage(base, patterns, max_files, max_bytes)
  out = []
  seen = {}
  total = 0
  patterns.each -> (p)
    next if rung_blank?(p)
    g = rung_glob(base, p)
    raise "stage: '[p]' matches no files" if g["files"].size == 0
    g["files"].each -> (f)
      rel = rung_relative(f, g["anchor"])
      rel = rung_basename(f) if rel == nil
      if seen[rel] != nil
        other = seen[rel]
        if other != f
          raise "stage: two files would both be staged as '[rel]' ([other] and [f])"
      else
        seen[rel] = f
        n = rung_file_size(f)
        total += n
        out.push({"src" => f, "rel" => rel, "bytes" => n})
  if out.size > max_files
    raise "stage: [out.size] files exceed the limit of [max_files] (trim the patterns or raise stage_max_files)"
  if total > max_bytes
    raise "stage: [total] bytes exceed the limit of [max_bytes] (trim the patterns or raise stage_max_bytes)"
  out

# Copy staged files (src -> dir/rel), read-only.
-> rung_stage_into(items, dir)
  rung_mkdir(dir)
  items.each -> (it)
    rung_copy_ro(it["src"], dir + "/" + it["rel"])
  dir

# A call's work dir: fresh copies of RUN/stage.
-> rung_make_workdir(run_dir, rels, workdir)
  rung_rm_rf(workdir)
  rung_mkdir(workdir)
  rels.each -> (rel)
    rung_copy_ro(run_dir + "/stage/" + rel, workdir + "/" + rel)
  workdir
