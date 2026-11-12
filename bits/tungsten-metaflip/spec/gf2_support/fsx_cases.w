# Cases for lib/metaflip/gf2/fsx.w and procx.w-backed temp directories, run by
# spec/gf2_support_test.w. Python 3.14's pathlib/os.path produced the goldens in
# spec/fixtures/gf2_support/fsx/ (gen_fsx_goldens.py): pure path arithmetic, glob results on a
# tree with dotfiles, spaces, unicode, symlinks, a dangling link and link loops, and resolve().
use ../../lib/metaflip/gf2/fsx
use core/crypto/sha256

# The fixture directory. A function of a `use`d file sees its own __DIR__ when compiled but the
# main program's when interpreted, so both layouts are tried; GF2_SUPPORT_FIXTURES overrides.
-> fsx_case_fixture_dir
  configured = env("GF2_SUPPORT_FIXTURES")
  return configured + "/fsx" if configured != nil && configured != ""
  candidates = [__DIR__ + "/../fixtures/gf2_support/fsx", __DIR__ + "/fixtures/gf2_support/fsx"]
  found = candidates.select -> (dir)
    File.exist?(dir + "/tree.txt")
  found.size > 0 ? found[0] : candidates[0]

# A golden TSV as rows of fields (empty fields kept).
-> fsx_case_rows(dir, name)
  text = read_file(dir + "/" + name)
  raise "missing fixture " + dir + "/" + name if text == nil
  rows = []
  text.split("\n").each -> (line)
    rows.push(line.split("\t")) unless line == ""
  rows

# Checks that the block raises an FsError of the given kind ("none": raises nothing; "other: text":
# some other error).
-> fsx_case_raises(t, label, expected, &)
  kind = "none"
  begin
    yield
  rescue e: FsError
    kind = e.kind
  rescue e
    kind = "other: " + e.to_s
  t.eq(label, kind, expected)

# Builds tree.txt below `root`: `d NAME`, `f NAME`, `l NAME TARGET` (TARGET ABS:x is root/x).
-> fsx_case_build_tree(dir, root)
  read_file(dir + "/tree.txt").split("\n").each -> (line)
    unless line == ""
      kind = line.slice(0, 1)
      rest = line.slice(2, line.size - 2)
      if kind == "d"
        Fsx.mkdir_p(Fsx.join(root, rest))
      elsif kind == "f"
        Fsx.mkdir_p(Fsx.dirname(Fsx.join(root, rest)))
        Fsx.write(Fsx.join(root, rest), "")
      else
        cut = rest.rindex(" ")
        target = rest.slice(cut + 1, rest.size - cut - 1)
        target = root + "/" + target.slice(4, target.size - 4) if target.starts_with?("ABS:")
        Procx.check_output(["ln", "-s", target, Fsx.join(root, rest.slice(0, cut))])

-> fsx_case_word(flag)
  flag ? "true" : "false"

# One parents.tsv row: `want` is the ancestor or "!" for IndexError.
# TODO(port): a block that captures the parameter of an enclosing block inside an if/else branch
# miscompiles ("undefined method '[]' for Object"), so the row is passed as plain arguments.
-> fsx_case_parent(t, path, levels, want)
  label = "parents.tsv \"" + path + "\" " + levels.to_s
  if want == "!"
    fsx_case_raises(t, label, "IndexError") ->
      Fsx.parent(path, levels)
  else
    t.eq(label, Fsx.parent(path, levels), want)

# Path arithmetic against pathlib.
-> fsx_case_paths(t, dir)
  fsx_case_rows(dir, "paths.tsv").each -> (row)
    path = row[0]
    got = [Fsx.join(path), Fsx.parts(path).join("|"), Fsx.basename(path), Fsx.dirname(path), Fsx.stem(path), Fsx.suffix(path), fsx_case_word(Fsx.absolute?(path))]
    t.eq("paths.tsv \"" + path + "\"", got, row.slice(1, 7))
  fsx_case_rows(dir, "join.tsv").each -> (row)
    t.eq("join.tsv " + row[0], Fsx.join_all(row[0].split("|")), row[1])
  fsx_case_rows(dir, "relative.tsv").each -> (row)
    want = row[2] == "!" ? nil : row[2]
    t.eq("relative.tsv \"" + row[0] + "\" in \"" + row[1] + "\"", Fsx.relative_to(row[0], row[1]), want)
    t.eq("relative? \"" + row[0] + "\" in \"" + row[1] + "\"", Fsx.relative?(row[0], row[1]), want != nil)
  fsx_case_rows(dir, "parents.tsv").each -> (row)
    fsx_case_parent(t, row[0], row[1].to_i, row[2])
  fsx_case_rows(dir, "expand.tsv").each -> (row)
    t.eq("expand.tsv \"" + row[0] + "\"", Fsx.expand_path(row[0], "/base/dir"), row[1])
  t.eq("expand_path defaults to the current directory", Fsx.expand_path("x/../y"), File.pwd + "/y")
  t.eq("join of nothing is dot", Fsx.join, ".")
  t.eq("join varargs", Fsx.join("a/", "b", "../c"), "a/b/../c")
  t.eq("sort_paths is component-wise", Fsx.sort_paths(["a/b", "a.b", "a-b", "a/b/c", "a0", "A", "a", "/x", "x"]), ["/x", "A", "a", "a/b", "a/b/c", "a-b", "a.b", "a0", "x"])
  t.eq("plain string order differs", ["a/b", "a.b", "a-b"].sort, ["a-b", "a.b", "a/b"])
  t.eq("sort_paths is stable and keeps equal paths", Fsx.sort_paths(["b", "a", "./a"]), ["a", "./a", "b"])

# fnmatch semantics of one path component.
-> fsx_case_wildcards(t)
  [["*", "", true], ["*", "abc", true], ["a*", "abc", true], ["a*", "bac", false], ["*c", "abc", true], ["*b*", "abc", true],
   ["a*b*c", "aXXbYYc", true], ["a*b*c", "aXXbYY", false], ["a?c", "abc", true], ["a?c", "ac", false], ["?", "é", true],
   ["??", "é", false], ["a?b", "aéb", true], ["*é*", "caféx", true], ["**", "anything", true], ["a**b", "ab", true],
   ["abc", "abc", true], ["abc", "abd", false], ["", "", true], ["", "a", false], ["*.mfw", "x.mfw.gz", false],
   ["*.mfw*", "x.mfw.gz", true], ["*a", "aaab", false], ["*aab", "aaab", true], [".*", ".hid", true], ["*", ".hid", true]].each -> (row)
    t.eq("wildcard_match? \"" + row[0] + "\" \"" + row[1] + "\"", Fsx.wildcard_match?(row[0], row[1]), row[2])

# Files: read/write/append/atomic_write/replace/unlink/size/mtime under hostile names.
-> fsx_case_files(t, root)
  path = Fsx.join(root, "sp ace 'q' \"d\" $x `y`.txt")
  t.eq("write returns the byte count", Fsx.write(path, "héllo\n"), 7)
  t.eq("read returns what was written", Fsx.read(path), "héllo\n")
  t.eq("append returns the byte count", Fsx.append(path, "more\n"), 5)
  t.eq("append extends the file", Fsx.read(path), "héllo\nmore\n")
  fresh = Fsx.join(root, "fresh.jsonl")
  Fsx.append(fresh, "{}\n")
  Fsx.append(fresh, "{}\n")
  t.eq("append creates the file", Fsx.read(fresh), "{}\n{}\n")
  t.eq("size is the byte count", Fsx.size(path), 12)
  t.ok("mtime_ns is a plausible timestamp", Fsx.mtime_ns(path) > 1000000000000000000)
  raw = Fsx.join(root, "with nul.bin")
  t.eq("write is NUL-safe", Fsx.write(raw, "a\0b\0"), 4)
  t.eq("append is NUL-safe", Fsx.append(raw, "\0c"), 2)
  t.eq("read is NUL-safe", Fsx.read(raw), "a\0b\0\0c")
  t.eq("size counts the NUL bytes", Fsx.size(raw), 6)
  t.eq("write replaces", Fsx.write(fresh, "x"), 1)
  t.eq("write replaced the content", Fsx.read(fresh), "x")
  missing = Fsx.join(root, "no such")
  fsx_case_raises(t, "read of a missing file", "FileNotFoundError") ->
    Fsx.read(missing)
  fsx_case_raises(t, "read of a directory", "IsADirectoryError") ->
    Fsx.read(root)
  fsx_case_raises(t, "write into a missing directory", "OSError") ->
    Fsx.write(Fsx.join(missing, "f"), "x")
  fsx_case_raises(t, "append into a missing directory", "OSError") ->
    Fsx.append(Fsx.join(missing, "f"), "x")
  fsx_case_raises(t, "size of a missing file", "FileNotFoundError") ->
    Fsx.size(missing)
  fsx_case_raises(t, "mtime_ns of a missing file", "FileNotFoundError") ->
    Fsx.mtime_ns(missing)
  # atomic_write
  target = Fsx.join(root, "atomic.json")
  t.eq("atomic_write returns the byte count", Fsx.atomic_write(target, "one"), 3)
  t.eq("atomic_write creates", Fsx.read(target), "one")
  Fsx.atomic_write(target, "two two")
  t.eq("atomic_write replaces", Fsx.read(target), "two two")
  litter = Fsx.entries(root).select -> (name)
    name.starts_with?("atomic")
  t.eq("atomic_write leaves no temporary file", litter, ["atomic.json"])
  fsx_case_raises(t, "atomic_write into a missing directory", "OSError") ->
    Fsx.atomic_write(Fsx.join(missing, "f"), "x")
  # replace
  source = Fsx.join(root, "source.txt")
  Fsx.write(source, "moved")
  t.eq("replace returns the destination", Fsx.replace(source, target), target)
  t.eq("replace overwrites the destination", Fsx.read(target), "moved")
  t.ok("replace consumed the source", !File.exist?(source))
  fsx_case_raises(t, "replace of a missing source", "OSError") ->
    Fsx.replace(source, target)
  # unlink
  t.eq("unlink removes the file", Fsx.unlink(target), true)
  t.ok("unlink really removed it", !File.exist?(target))
  fsx_case_raises(t, "unlink of a missing file", "FileNotFoundError") ->
    Fsx.unlink(target)
  t.eq("unlink of a missing file with missing_ok", Fsx.unlink(target, missing_ok: true), false)
  fsx_case_raises(t, "unlink of a directory", "IsADirectoryError") ->
    Fsx.unlink(root)

# Directories: mkdir/mkdir_p/entries/remove_tree and symlink safety.
-> fsx_case_dirs(t, root)
  made = Fsx.join(root, "made")
  t.eq("mkdir returns the path", Fsx.mkdir(made), made)
  t.ok("mkdir created it", File.directory?(made))
  fsx_case_raises(t, "mkdir of an existing directory", "FileExistsError") ->
    Fsx.mkdir(made)
  t.eq("mkdir exist_ok accepts an existing directory", Fsx.mkdir(made, exist_ok: true), made)
  deep = Fsx.join(made, "a b/c")
  fsx_case_raises(t, "mkdir without parents needs the parent", "FileNotFoundError") ->
    Fsx.mkdir(deep)
  t.eq("mkdir parents creates the chain", Fsx.mkdir(deep, parents: true), deep)
  t.ok("the chain exists", File.directory?(deep))
  t.eq("mkdir_p is idempotent", Fsx.mkdir_p(deep), deep)
  Fsx.write(Fsx.join(made, "file"), "x")
  fsx_case_raises(t, "mkdir over a file", "FileExistsError") ->
    Fsx.mkdir(Fsx.join(made, "file"))
  fsx_case_raises(t, "mkdir exist_ok over a file", "FileExistsError") ->
    Fsx.mkdir(Fsx.join(made, "file"), exist_ok: true)
  fsx_case_raises(t, "mkdir_p through a file", "NotADirectoryError") ->
    Fsx.mkdir_p(Fsx.join(made, "file/x"))
  # entries
  Fsx.write(Fsx.join(made, ".hidden"), "")
  Fsx.write(Fsx.join(made, "Zed"), "")
  Fsx.write(Fsx.join(made, "alpha"), "")
  t.eq("entries are sorted bytewise and include hidden names", Fsx.entries(made), [".hidden", "Zed", "a b", "alpha", "file"])
  empty = Fsx.mkdir(Fsx.join(root, "empty"))
  t.eq("entries of an empty directory", Fsx.entries(empty), [])
  fsx_case_raises(t, "entries of a missing directory", "FileNotFoundError") ->
    Fsx.entries(Fsx.join(root, "gone"))
  fsx_case_raises(t, "entries of a file", "NotADirectoryError") ->
    Fsx.entries(Fsx.join(made, "file"))
  # remove_tree never follows a symlink
  outside = Fsx.mkdir(Fsx.join(root, "outside"))
  Fsx.write(Fsx.join(outside, "keep.txt"), "keep")
  Procx.check_output(["ln", "-s", outside, Fsx.join(made, "escape")])
  t.eq("remove_tree removes the tree", Fsx.remove_tree(made), true)
  t.ok("the tree is gone", !File.exist?(made))
  t.eq("remove_tree did not follow the symlink", Fsx.read(Fsx.join(outside, "keep.txt")), "keep")
  t.eq("remove_tree of a missing path", Fsx.remove_tree(made), false)
  fsx_case_raises(t, "remove_tree refuses the empty path", "ValueError") ->
    Fsx.remove_tree("")
  fsx_case_raises(t, "remove_tree refuses the root", "ValueError") ->
    Fsx.remove_tree("/")
  fsx_case_raises(t, "remove_tree refuses the root spelled oddly", "ValueError") ->
    Fsx.remove_tree("//")
  link = Fsx.join(root, "a link")
  Procx.check_output(["ln", "-s", outside, link])
  t.eq("remove_tree of a symlink removes only the link", Fsx.remove_tree(link), true)
  t.ok("the link target survives", File.exist?(Fsx.join(outside, "keep.txt")))
  t.ok("the link is gone", File.lstat(link) == nil)

# Temporary directories, pid, home.
-> fsx_case_process(t)
  one = Fsx.tempdir
  two = Fsx.tempdir(prefix: "gf2 x-")
  t.ok("tempdir creates a directory", File.directory?(one) && File.directory?(two))
  t.ok("tempdir names differ", one != two)
  t.ok("tempdir honours the prefix", Fsx.basename(two).starts_with?("gf2 x-") && Fsx.basename(one).starts_with?("tmp"))
  base = env("TMPDIR")
  base = "/tmp" if base == nil || base == ""
  t.eq("tempdir lives under TMPDIR", Fsx.relative?(one, Fsx.expand_path(base)), true)
  fsx_case_raises(t, "tempdir rejects a slash in the prefix", "ValueError") ->
    Fsx.tempdir(prefix: "a/b")
  Fsx.remove_tree(one)
  Fsx.remove_tree(two)
  seen = nil
  value = Fsx.with_tempdir(prefix: "gf2-with-") -> (dir)
    seen = dir
    Fsx.write(Fsx.join(dir, "f"), "x")
    "block value"
  t.eq("with_tempdir returns the block's value", value, "block value")
  t.ok("with_tempdir removed the directory", seen != nil && !File.exist?(seen))
  seen = nil
  fsx_case_raises(t, "with_tempdir passes the block's error through", "other: boom") ->
    Fsx.with_tempdir(prefix: "gf2-raise-") -> (dir)
      seen = dir
      raise "boom"
  t.ok("with_tempdir removed the directory after the raise", seen != nil && !File.exist?(seen))
  t.eq("home is $HOME", Fsx.home, env("HOME"))
  first = Fsx.pid
  t.ok("pid is a positive integer", first > 0)
  t.eq("pid is stable", Fsx.pid, first)
  t.ok("pid names a live process", Procx.succeeds?(["kill", "-0", first.to_s]))

# glob/rglob/walk/resolve against the golden tree.
-> fsx_case_tree(t, dir, root)
  fsx_case_build_tree(dir, root)
  fsx_case_rows(dir, "glob.tsv").each -> (row)
    found = Fsx.glob(root, row[0], files_only: row[1] == "files")
    shown = found.map -> (path)
      Fsx.relative_to(path, root) || "?"
    t.eq("glob(" + row[0] + ") " + row[1], shown.join("|"), row[2])
  t.eq("glob is root-joined", Fsx.glob(root + "/", "a/g.txt"), [root + "/a/g.txt"])
  t.eq("glob under a relative root is relative", Fsx.glob(".", "nothing-here-*"), [])
  t.eq("rglob = glob **/", Fsx.rglob(root, "*.mfw"), Fsx.glob(root, "**/*.mfw"))
  t.eq("rglob files_only", Fsx.rglob(root, "*", files_only: true).size, Fsx.glob(root, "**/*", files_only: true).size)
  fsx_case_raises(t, "glob rejects an absolute pattern", "ValueError") ->
    Fsx.glob(root, "/etc/*")
  fsx_case_raises(t, "glob rejects an empty pattern", "ValueError") ->
    Fsx.glob(root, "")
  fsx_case_raises(t, "glob rejects character sets", "ValueError") ->
    Fsx.glob(root, "\[ab\]*")
  relative = File.chdir(root) ->
    [Fsx.glob(".", "a/*.txt"), Fsx.glob("a", "*.txt"), Fsx.glob(".", "**/f.txt"), Fsx.walk("a"), Fsx.glob("", "lnk"), Fsx.resolve("lnk/b")]
  t.eq("glob with root . gives bare relative names", relative[0], ["a/g.txt"])
  t.eq("glob under a relative directory", relative[1], ["a/g.txt"])
  t.eq("rglob-style pattern from .", relative[2], ["a/b/f.txt"])
  t.eq("walk of a relative directory", relative[3], ["a/b/f.txt", "a/g.txt"])
  t.eq("glob with an empty root is the current directory", relative[4], ["lnk"])
  t.eq("resolve of a relative path through a link", relative[5], Fsx.resolve(root) + "/a/b")
  t.eq("glob under a missing root is empty", Fsx.glob(Fsx.join(root, "nope"), "*"), [])
  t.eq("glob under a file is empty", Fsx.glob(Fsx.join(root, "best.txt"), "*"), [])
  walked = Fsx.walk(root)
  not_files = walked.select -> (path)
    !Fsx.regular?(path)
  t.eq("walk lists only files", not_files, [])
  through_links = walked.select -> (path)
    path.include?("/lnk/") || path.include?("/loop/")
  t.eq("walk does not enter symlinked directories", through_links, [])
  mfw = Fsx.walk(root, suffix: ".mfw").map -> (path)
    Fsx.relative_to(path, root)
  t.eq("walk with a suffix", mfw, ["deep/top.mfw", "deep/x/w.mfw", "deep/x/y/z.mfw"])
  t.eq("walk of an empty directory", Fsx.walk(Fsx.join(root, "empty")), [])
  fsx_case_rows(dir, "resolve.tsv").each -> (row)
    resolved = Fsx.relative_to(Fsx.resolve(root + "/" + row[0]), Fsx.resolve(root)) || "OUTSIDE"
    t.eq("resolve " + row[0], resolved, row[1])
  t.eq("resolve of the root itself", Fsx.resolve(root + "/."), Fsx.resolve(root))
  t.eq("resolve of a relative path uses the current directory", Fsx.resolve("some/where/../else"), Fsx.resolve(File.pwd) + "/some/else")
  t.eq("resolve of the filesystem root", Fsx.resolve("/"), "/")
  t.eq("resolve above the root stays at the root", Fsx.resolve("/../.."), "/")

-> fsx_case_work_dir
  configured = env("GF2_RECORD_HUNT_WORK")
  return configured if configured != nil && configured != ""
  "/Users/erik/.tungsten/metaflip/experiments/record-hunt-20260926/work"

# glob on the campaign's own directories against Python's pathlib (real_glob.tsv, made by
# gen_fsx_goldens.py from the work directory): the same matches in the same order.
-> fsx_case_real(t, dir)
  work = fsx_case_work_dir
  unless File.directory?(work + "/release-0929")
    << "SKIP fsx real trees: no record-hunt work directory at " + work
    return nil
  fsx_case_rows(dir, "real_glob.tsv").each -> (row)
    root = Fsx.join(work, row[0])
    if File.directory?(root)
      found = Fsx.glob(root, row[1], files_only: row[2] == "files")
      names = found.map -> (path)
        Fsx.relative_to(path, root)
      label = "real glob " + row[0] + " " + row[1] + " " + row[2]
      t.eq(label + ": count", names.size, row[3].to_i)
      t.eq(label + ": names and order", Crypto:SHA256.hexdigest(names.join("\n") + "\n"), row[4])
  nil

-> gf2_fsx_cases(t)
  dir = fsx_case_fixture_dir
  fsx_case_paths(t, dir)
  fsx_case_wildcards(t)
  fsx_case_process(t)
  Fsx.with_tempdir(prefix: "gf2-fsx-") -> (root)
    fsx_case_files(t, root)
    fsx_case_dirs(t, root)
  Fsx.with_tempdir(prefix: "gf2-tree-") -> (root)
    fsx_case_tree(t, dir, root)
  fsx_case_real(t, dir)
