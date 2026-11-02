use core/file

# Path — immutable filesystem path
#
# Constructor: Path("/usr/bin")
#
# Examples:
#   p = Path("/usr/bin/ruby")
#   p.parent     # Path("/usr/bin")
#   p.name       # "ruby"
#   p.extension  # ""
#   p / "lib"    # Path("/usr/bin/ruby/lib")
#   p.join("lib", "site") # Path("/usr/bin/ruby/lib/site")
#   p.exist?     # true
#   Path(".").each -> (child)
#     << child.name
+ Path
  is Enumerable

  ro :path

  -> new(path)
    @path = path.to_s

  -> parent
    return Path.new("/") if @path == "/"
    s = @path
    while s.size > 1 && s.ends_with?("/")
      s = s.slice(0, s.size - 1)
    idx = s.rindex("/")
    return Path.new(".") if idx == nil
    return Path.new("/") if idx == 0
    Path.new(s.slice(0, idx))

  -> name
    return "/" if @path == "/"
    s = @path
    while s.size > 1 && s.ends_with?("/")
      s = s.slice(0, s.size - 1)
    idx = s.rindex("/")
    return s if idx == nil
    s.slice(idx + 1, s.size - idx - 1)

  -> stem
    base = self.name()
    dot = base.rindex(".")
    return base if dot == nil || dot == 0
    base.slice(0, dot)

  -> extension
    base = self.name()
    dot = base.rindex(".")
    return "" if dot == nil || dot == 0
    base.slice(dot + 1, base.size - dot - 1)

  -> root
    return Path.new("/") if @path.starts_with?("/")
    nil

  -> absolute?
    @path.starts_with?("/")

  -> home_relative?
    @path == "~" || @path.starts_with?("~/")

  -> segments
    parts = @path.split("/")
    out = []
    i = 0
    while i < parts.size
      if parts[i].size > 0
        out.push(parts[i])
      i += 1
    out

  -> exist?
    File.exist?(@path)

  -> file?
    File.file?(@path)

  -> directory?
    File.directory?(@path)

  -> symlink?
    File.symlink?(@path)

  -> type
    File.type(@path)

  -> file_type
    File.file_type(@path)

  # entries returns filenames; children/ls/each return child Path objects.
  -> entries
    read_dir(@path)

  -> children
    names = read_dir(@path)
    return [] if names == nil
    out = []
    i = 0
    while i < names.size
      out.push(Path.new(file_join(@path, names[i])))
      i += 1
    out

  -> ls
    self.children()

  -> each(&)
    kids = self.children()
    i = 0
    while i < kids.size
      yield kids[i]
      i += 1
    self

  -> empty?
    names = read_dir(@path)
    names == nil || names.size == 0

  -> join(*paths)
    acc = @path
    i = 0
    while i < paths.size
      acc = file_join(acc, paths[i].to_s)
      i += 1
    Path.new(acc)

  -> /(other)
    Path.new(file_join(@path, other.to_s))

  -> expand
    Path.new(file_expand_path(@path))

  -> mtime
    ns = file_mtime_ns(@path)
    return nil if ns == nil
    ns / 1_000_000_000

  -> mtime_ns
    file_mtime_ns(@path)

  -> size
    file_size(@path)

  -> ==(other)
    other.is_a?(Path) && @path == other.to_s

  -> hash
    @path.hash

  -> to_s
    @path

  -> inspect
    @path
