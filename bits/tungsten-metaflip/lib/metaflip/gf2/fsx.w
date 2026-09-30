# Fsx: the filesystem and path operations the Python tools get from pathlib, os.path, glob,
# shutil and tempfile, for a language whose File class stops short of them.
#
# What core already does is reused (File.mkdir/mkdir_p/rm/rmdir/rename/atomic_write/lstat/size/
# mtime_ns, read_dir, read_file, write_file, tempfile_create). What it lacks or does not wire in
# the compiled runtime is added here: File.basename/dirname/extname/realpath/readlink/file? are
# undefined there, File.join only concatenates, File.expand_path normalises nothing, there is no
# glob, no append, no temporary directory. Paths are plain Strings.
#
# Path arithmetic follows pathlib (PurePosixPath, Python 3.14), not os.path: components are
# split on "/", empty and "." components vanish, ".." is kept, a leading "//" is a distinct
# root. Everything below is purely lexical except resolve, size, mtime_ns and the calls that
# touch the disk. The goldens in spec/fixtures/gf2_support/fsx/ come from Python 3.14.
#
# Who needs what (the original idiom in brackets):
#   read write append          [Path.read_text/write_text, open(log, 'a') in every campaign driver]
#   mkdir mkdir_p              [out.mkdir(parents=True, exist_ok=False) in build_gf2_lineage_bundle.py,
#                               os.makedirs(..., exist_ok=True) in mmc_gf2_replay.py]
#   entries glob rglob walk    [root.rglob('*.mfw') in gf2_record_board.py, base.glob('matmul_*_gf2.txt')
#                               in wide_composition_recipes.py, glob.glob(WORK / 'mat*/seeds.json') in
#                               collect_chains.py, HERE.glob('keep/**/*.mfw') in board.py]
#   sort_paths                 [sorted(set(sources())) of Path objects in board.py]
#   atomic_write replace       [tmp.write_text(); os.replace(tmp, cp) in mmc_gf2_replay.py Source.raw,
#                               temporary.replace(target) in search_wide_projection_walks.py]
#   unlink remove_tree         [out.unlink() in screen_public_ternary_gf2.py, TemporaryDirectory cleanup]
#   join basename dirname stem suffix parts absolute? parent relative_to relative? expand_path
#                              [root / source, .name, .parent, log.stem, f.suffix, source.parts,
#                               source.is_absolute(), Path(__file__).resolve().parents[3],
#                               Path(p).relative_to(REPO), path.is_relative_to(root)]
#   resolve                    [(root / source).resolve() before the is_relative_to guard in
#                               wide_composition_recipes.py, Path(...).resolve() in collect_chains.py]
#   size mtime_ns              [log.stat().st_size in write_readmes.py; File.mtime_ns in build_cache]
#   tempdir with_tempdir       [tempfile.TemporaryDirectory() in verify_gf2_lineage.py]
#   home pid                   [Path.home() in board.py; os.getpid() in mmc_gf2_replay.py]
use procx

# Raised by every Fsx call that fails. `kind` is the Python exception it stands for
# (FileNotFoundError, FileExistsError, NotADirectoryError, IsADirectoryError, ValueError,
# OSError); the message starts with it.
+ FsError < Error
  -> new(@message, @kind)
  ro :kind

+ Fsx
  # ---- reading and writing files -------------------------------------------------------

  # Path.read_text(): the file's content; FsError (FileNotFoundError) when it cannot be read.
  -> .read(path)
    text = read_file(path)
    raise Fsx.failure(path, "cannot read", Fsx.access_kind(path)) if text == nil
    text

  # Path.write_text(): writes `data`, replacing the file; the number of bytes written. FsError when
  # it cannot be written (write_file alone would answer false and let a tool report success).
  -> .write(path, data)
    raise Fsx.failure(path, "cannot write") unless write_file(path, data)
    data.size

  # open(path, 'a').write(text): appends `text`, creating the file; the number of bytes written.
  # FsError on failure.
  # TODO(port): File.open is unwired in the compiled runtime (file_open is undefined), so this
  # calls the runtime's append primitive directly.
  -> .append(path, text)
    raise Fsx.failure(path, "cannot append to") unless ccall("__w_append_file", path, text)
    text.size

  # File.atomic_write: writes beside `path` and renames over it, so a reader sees the old or the
  # new content, never a partial file (the temp-file-plus-os.replace idiom). Returns the byte count.
  -> .atomic_write(path, data)
    begin
      File.atomic_write(path, data)
    rescue e
      raise FsError.new("OSError: " + e.to_s, "OSError")
    data.size

  # os.replace / Path.replace: renames `source` over `destination` atomically.
  -> .replace(source, destination)
    unless file_rename(source, destination)
      raise FsError.new("OSError: cannot rename " + source + " to " + destination, "OSError")
    destination

  # Path.unlink(missing_ok=False): removes a file or symlink. A missing path raises unless
  # missing_ok; a directory always raises (IsADirectoryError). True when something was removed.
  -> .unlink(path, missing_ok: false)
    status = File.lstat(path)
    if status == nil
      return false if missing_ok
      raise Fsx.failure(path, "no such file", "FileNotFoundError")
    if status.directory?
      raise Fsx.failure(path, "is a directory", "IsADirectoryError")
    raise Fsx.failure(path, "cannot remove") unless File.rm(path)
    true

  # shutil.rmtree, but like `rm -rf`: a missing path is not an error (false). Symlinks are
  # removed, never followed. Refuses "" and the root, which are always mistakes.
  -> .remove_tree(path)
    pieces = Fsx.parts(path)
    if pieces.size == 0 || (pieces.size == 1 && Fsx.absolute?(pieces[0]))
      raise Fsx.failure(path, "refusing to remove", "ValueError")
    status = File.lstat(path)
    return false if status == nil
    if status.directory?
      (read_dir(path) || []).each -> (name)
        Fsx.remove_tree(Fsx.join(path, name))
      raise Fsx.failure(path, "cannot remove directory") unless File.rmdir(path)
    else
      raise Fsx.failure(path, "cannot remove") unless File.rm(path)
    true

  # Path.stat().st_size, in bytes.
  -> .size(path)
    bytes = File.size(path)
    raise Fsx.failure(path, "no such file", "FileNotFoundError") if bytes == nil
    bytes

  # Path.stat().st_mtime_ns.
  -> .mtime_ns(path)
    stamp = File.mtime_ns(path)
    raise Fsx.failure(path, "no such file", "FileNotFoundError") if stamp == nil
    stamp

  # ---- directories ---------------------------------------------------------------------

  # Path.mkdir(parents=, exist_ok=) with Python's defaults (both false). An existing directory
  # is fine only with exist_ok; anything else in the way is FileExistsError; a missing parent is
  # FileNotFoundError unless parents. Returns the path.
  -> .mkdir(path, parents: false, exist_ok: false)
    if File.directory?(path)
      return path if exist_ok
      raise Fsx.failure(path, "already exists", "FileExistsError")
    raise Fsx.failure(path, "already exists", "FileExistsError") if File.lstat(path) != nil
    if !parents && !File.directory?(Fsx.dirname(path))
      raise Fsx.failure(path, "parent directory is missing", "FileNotFoundError")
    made = parents ? File.mkdir_p(path) : File.mkdir(path)
    raise Fsx.failure(path, "cannot create directory", Fsx.creation_kind(path)) unless made
    path

  # os.makedirs(path, exist_ok=True): the directory and its missing parents.
  -> .mkdir_p(path)
    Fsx.mkdir(path, parents: true, exist_ok: true)

  # sorted(os.listdir(path)): the names in a directory, byte order, without "." and "..".
  -> .entries(path)
    names = read_dir(path)
    if names == nil
      kind = File.lstat(path) == nil ? "FileNotFoundError" : "NotADirectoryError"
      raise Fsx.failure(path, "cannot list", kind)
    names.sort

  # ---- searching -----------------------------------------------------------------------

  # Path(root).glob(pattern) for the patterns the tools use: `*` and `?` inside a path
  # component, and `**` as a whole component (any number of directories, including none, never
  # through a symlink; as the last component it matches every file and directory below, and
  # `root` itself). Hidden names match `*`, as in pathlib. Intermediate components follow
  # symlinks, as pathlib does. `[...]` sets are refused (ValueError). Results are `root` joined
  # to the match, in pathlib's sorted-path order (see sort_paths), each once; under the root "." or
  # "" they are bare relative names. files_only keeps regular files (and symlinks to them).
  -> .glob(root, pattern, files_only: false)
    if pattern.to_s == "" || pattern.starts_with?("/") || pattern.index("\[") != nil
      raise Fsx.failure(pattern, "unsupported glob pattern", "ValueError")
    pieces = []
    pattern.split("/").each -> (piece)
      pieces.push(piece) unless piece == "" || piece == "."
    found = {}
    Fsx.glob_step(root.to_s == "" ? "." : root, "", pieces, 0, found)
    hits = Fsx.sort_paths(found.keys)
    out = []
    hits.each -> (relative)
      whole = Fsx.glob_result(root, relative)
      out.push(whole) unless files_only && !Fsx.regular?(whole)
    out

  # Path(root).rglob(pattern): glob(root, "**/" + pattern).
  -> .rglob(root, pattern, files_only: false)
    Fsx.glob(root, "**/" + pattern, files_only: files_only)

  # Every regular file below `root` in sorted-path order, optionally only names ending in
  # `suffix` (".tex"). Symlinked directories are not entered.
  -> .walk(root, suffix: nil)
    files = Fsx.glob(root, "**", files_only: true)
    return files if suffix == nil
    files.select -> (file)
      file.ends_with?(suffix)

  # sorted(paths) for pathlib paths: component by component, so "a/b" sorts before "a.b" and
  # "a-b" (plain string order would put "/" after "-" and ".").
  -> .sort_paths(paths)
    paths.sort_by -> (path)
      Fsx.parts(path)

  # ---- path arithmetic (pathlib.PurePosixPath) -----------------------------------------

  # PurePath.parts: the components; an absolute path starts with its root "/" ("//" when it
  # begins with exactly two slashes). "" and "." have no parts.
  -> .parts(path)
    text = path.to_s
    pieces = []
    text.split("/").each -> (piece)
      pieces.push(piece) unless piece == "" || piece == "."
    return pieces unless text.starts_with?("/")
    root = text.starts_with?("//") && !text.starts_with?("///") ? "//" : "/"
    [root] + pieces

  # True for a path that starts with "/" (PurePath.is_absolute).
  -> .absolute?(path)
    path.to_s.starts_with?("/")

  # Path(a, b, ...) / ...: joins with "/" and normalises like pathlib. A later absolute path
  # replaces everything before it; nothing at all is ".".
  -> .join(*paths)
    Fsx.join_all(paths)

  # join for an Array of pieces (Tungsten has no splat at the call site).
  -> .join_all(pieces)
    current = []
    pieces.each -> (piece)
      current = [] if Fsx.absolute?(piece)
      current = current + Fsx.parts(piece)
    Fsx.unparse(current)

  # PurePath.name: the last component ("" for the root and for ".").
  -> .basename(path)
    pieces = Fsx.parts(path)
    return "" if pieces.size == 0 || Fsx.absolute?(pieces.last)
    pieces.last

  # PurePath.parent: everything but the last component; "." for a bare name, the root for the root.
  -> .dirname(path)
    pieces = Fsx.parts(path)
    return "." if pieces.size == 0
    return Fsx.unparse(pieces) if pieces.size == 1 && Fsx.absolute?(pieces[0])
    Fsx.unparse(pieces.slice(0, pieces.size - 1))

  # PurePath.parents[levels - 1]: the ancestor `levels` up (Path(__file__).resolve().parents[3]).
  # FsError (IndexError) when the path has fewer components.
  -> .parent(path, levels = 1)
    pieces = Fsx.parts(path)
    depth = pieces.size
    depth -= 1 if depth > 0 && Fsx.absolute?(pieces[0])
    if levels < 1 || levels > depth
      raise Fsx.failure(path, "has no ancestor " + levels.to_s + " levels up", "IndexError")
    Fsx.unparse(pieces.slice(0, pieces.size - levels))

  # PurePath.suffix: the last dot-extension of the name (".gz" of "a.tar.gz"); "" when the name
  # has no dot after its first non-dot character. Python 3.14 rules: "a." has suffix ".".
  -> .suffix(path)
    name = Fsx.basename(path)
    cut = Fsx.suffix_start(name)
    cut == nil ? "" : name.slice(cut, name.size - cut)

  # PurePath.stem: the name without its suffix.
  -> .stem(path)
    name = Fsx.basename(path)
    cut = Fsx.suffix_start(name)
    cut == nil ? name : name.slice(0, cut)

  # PurePath.relative_to(base) for the case where `path` is inside `base`: the remainder ("."
  # when they are equal). nil when it is not, where Python raises ValueError (collect_chains.py
  # classify_committed catches exactly that).
  -> .relative_to(path, base)
    below = Fsx.parts(path)
    above = Fsx.parts(base)
    return nil if above.size > below.size
    return nil if Fsx.absolute?(path) != Fsx.absolute?(base)
    return nil if below.slice(0, above.size) != above
    Fsx.unparse(below.slice(above.size, below.size - above.size))

  # PurePath.is_relative_to(base).
  -> .relative?(path, base)
    Fsx.relative_to(path, base) != nil

  # os.path.abspath(join(base, path)): absolute and lexically normalised ("a/../b" -> "b"); a
  # relative path is taken relative to `base` (default: the current directory). Symlinks are not
  # consulted; see resolve.
  -> .expand_path(path, base = nil)
    start = base == nil ? File.pwd : Fsx.expand_path(base)
    whole = Fsx.parts(Fsx.join(start, path))
    kept = []
    whole.each -> (piece)
      if piece == ".."
        kept.pop if kept.size > 0 && !Fsx.absolute?(kept.last)
      else
        kept.push(piece)
    Fsx.unparse(kept)

  # Path.resolve(): absolute, symlinks followed component by component, ".." applied to the
  # resolved prefix, and a tail that does not exist kept as written. A port of
  # posixpath.realpath(strict=False): each resolved link is cached, and a link met again while
  # it is still being resolved (a loop) stays as it is.
  -> .resolve(path)
    text = path.to_s
    resolved = text.starts_with?("/") ? "/" : File.pwd
    rest = text.split("/").reverse
    left = rest.size
    seen = {}
    while left > 0
      name = rest.pop
      if name == nil
        seen[rest.pop] = resolved
        next
      left -= 1
      next if name == "" || name == "."
      if name == ".."
        resolved = Fsx.dirname(resolved)
        next
      candidate = resolved == "/" ? "/" + name : resolved + "/" + name
      status = File.lstat(candidate)
      if status == nil || !status.symlink?
        resolved = candidate
        next
      if seen.key?(candidate)
        cached = seen[candidate]
        resolved = cached == false ? candidate : cached
        next
      target = Fsx.readlink(candidate)
      if target == nil
        resolved = candidate
        next
      resolved = "/" if target.starts_with?("/")
      seen[candidate] = false
      rest.push(candidate)
      rest.push(nil)
      pieces = target.split("/").reverse
      pieces.each -> (piece)
        rest.push(piece)
      left += pieces.size
    resolved

  # ---- temporary directories and process facts -----------------------------------------

  # tempfile.mkdtemp(prefix=): a new empty directory under $TMPDIR (or /tmp); its path.
  -> .tempdir(prefix: "tmp")
    raise Fsx.failure(prefix, "bad temporary directory prefix", "ValueError") if prefix.index("/") != nil
    base = env("TMPDIR")
    base = "/tmp" if base == nil || base == ""
    while base.size > 1 && base.ends_with?("/")
      base = base.slice(0, base.size - 1)
    Procx.check_output(["mktemp", "-d", base + "/" + prefix + "XXXXXXXX"]).strip

  # with tempfile.TemporaryDirectory(prefix=) as dir: the block gets a fresh directory, which is
  # removed afterwards even when the block raises. Returns the block's value.
  -> .with_tempdir(prefix: "tmp", &)
    dir = Fsx.tempdir(prefix: prefix)
    begin
      yield dir
    ensure
      Fsx.remove_tree(dir)

  # Path.home().
  -> .home
    env("HOME")

  # os.getpid(): the id of the calling process (asks a shell, so cache it in a loop).
  # TODO(port): the runtime has no getpid builtin; the shell's $PPID is this process.
  -> .pid
    capture("echo $PPID").strip.to_i

  # ---- internals -----------------------------------------------------------------------

  # os.readlink, for resolve: the target a symlink points to, or nil when it cannot be read.
  # TODO(port): File.readlink is not wired in the compiled runtime (file_readlink is undefined),
  # so this asks readlink(1).
  -> .readlink(path)
    answer = Procx.run(["readlink", path], stderr: :null)
    return nil unless answer.ok?
    answer.out.ends_with?("\n") ? answer.out.slice(0, answer.out.size - 1) : answer.out

  # Why creating `path` failed: NotADirectoryError when an ancestor exists but is not a
  # directory, OSError otherwise.
  -> .creation_kind(path)
    ancestor = Fsx.dirname(path)
    while ancestor != "." && ancestor != "/" && File.lstat(ancestor) == nil
      ancestor = Fsx.dirname(ancestor)
    return "OSError" if File.directory?(ancestor) || File.lstat(ancestor) == nil
    "NotADirectoryError"

  # The Python exception a failed open() of `path` would have raised.
  -> .access_kind(path)
    status = File.lstat(path)
    return "FileNotFoundError" if status == nil
    status.directory? ? "IsADirectoryError" : "OSError"

  # The FsError for a failed operation: "Kind: verb: path".
  -> .failure(path, what, kind = "OSError")
    FsError.new(kind + ": " + what + ": " + path.to_s, kind)

  # Path pieces back to a string: "." for none, the root glued to the first name, "/" between.
  -> .unparse(pieces)
    return "." if pieces.size == 0
    return pieces[0] if pieces.size == 1
    return pieces[0] + pieces.slice(1, pieces.size - 1).join("/") if Fsx.absolute?(pieces[0])
    pieces.join("/")

  # Index of the dot that starts the suffix of `name`, or nil.
  -> .suffix_start(name)
    dot = name.rindex(".")
    return nil if dot == nil || dot == 0
    lead = name.bytes
    at = 0
    while at < dot && lead[at] == 46
      at += 1
    at == dot ? nil : dot

  # True for a regular file, following symlinks.
  -> .regular?(path)
    status = File.stat(path)
    status != nil && status.file?

  # `root` joined to a glob result; a "." root gives the bare relative name, as pathlib does.
  -> .glob_result(root, relative)
    return relative if root.to_s == "." || root.to_s == ""
    relative == "" ? root : Fsx.join(root, relative)

  # One step of glob: match `pieces[at..]` below directory `dir` (whose path relative to the
  # glob root is `relative`) and record every complete match in `found`.
  -> .glob_step(dir, relative, pieces, at, found)
    if at == pieces.size
      found[relative] = true
      return nil
    piece = pieces[at]
    last = at == pieces.size - 1
    if piece == "**"
      stack = [[dir, relative]]
      while stack.size > 0
        here = stack.pop
        listing = read_dir(here[0]) || []
        found[here[1]] = true if last
        listing.sort.each -> (name)
          child = Fsx.join(here[0], name)
          child_relative = here[1] == "" ? name : here[1] + "/" + name
          status = File.lstat(child)
          if status != nil && status.directory?
            stack.push([child, child_relative])
          elsif last
            found[child_relative] = true
        Fsx.glob_step(here[0], here[1], pieces, at + 1, found) unless last
      return nil
    if piece.index("*") == nil && piece.index("?") == nil
      names = File.lstat(Fsx.join(dir, piece)) == nil ? [] : [piece]
    else
      names = (read_dir(dir) || []).select -> (name)
        Fsx.wildcard_match?(piece, name)
    names.each -> (name)
      child = Fsx.join(dir, name)
      child_relative = relative == "" ? name : relative + "/" + name
      if last
        found[child_relative] = true
      elsif File.directory?(child)
        Fsx.glob_step(child, child_relative, pieces, at + 1, found)
    nil

  # fnmatch for one path component: `*` is any run of characters, `?` exactly one character
  # (a whole UTF-8 sequence); everything else matches itself.
  -> .wildcard_match?(pattern, name)
    p = pattern.bytes
    s = name.bytes
    pi = 0 ## i64
    si = 0 ## i64
    star = -1 ## i64
    mark = 0 ## i64
    while si < s.size
      if pi < p.size && p[pi] == 42
        star = pi
        mark = si
        pi += 1
      elsif pi < p.size && p[pi] == 63
        si += Fsx.sequence_width(s[si])
        pi += 1
      elsif pi < p.size && p[pi] == s[si]
        si += 1
        pi += 1
      elsif star >= 0
        mark += Fsx.sequence_width(s[mark])
        si = mark
        pi = star + 1
      else
        return false
    while pi < p.size && p[pi] == 42
      pi += 1
    pi == p.size

  # Bytes in the UTF-8 sequence that starts with `lead`.
  -> .sequence_width(lead)
    return 2 if lead >= 192 && lead < 224
    return 3 if lead >= 224 && lead < 240
    return 4 if lead >= 240 && lead < 248
    1
