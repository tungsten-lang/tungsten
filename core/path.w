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

  -> new(path)
  -> parent
  -> name
  -> stem
  -> extension
  -> root
  -> absolute?
  -> home_relative?
  -> segments
  -> exist?
  -> file?
  -> directory?
  -> symlink?
  -> type
  -> file_type
  # entries returns filenames; children/ls/each return child Path objects.
  -> entries
  -> children
  -> ls
  -> each(&)
  -> empty?
  -> join(*paths)
  -> expand
  -> mtime
  -> mtime_ns
  -> size
  -> to_s
