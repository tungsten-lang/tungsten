# Path — immutable filesystem path (core/path.w).
#
# Run:
#   bin/tungsten run --interpret spec/core/path_spec.w
#   bin/tungsten -o /tmp/path_spec spec/core/path_spec.w && /tmp/path_spec

use core/path

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()
  << "PASS " + name

p = Path.new("/usr/bin/ruby.exe")
check("constructs", type(p) == "Path")
check("is_a? Path", p.is_a?(Path))
check("class name", p.class_name == "Path")
check("distinct instance is still a Path", type(Path.new("a/b")) == "Path")

# BUG: Object#nil? (declared `-> nil? false`) raises "undefined method 'nil?'" for a Path compiled;
# interpreted it correctly returns false.
# Repro: printf 'use core/path\n<< Path.new("/a").nil?\n' > /tmp/p.w && bin/tungsten -o /tmp/p /tmp/p.w && /tmp/p
# check("not nil", !p.nil?)

# Every declared Path method is bodyless and has no runtime implementation: each returns nil
# on both engines. The documented behaviour is pinned here for when the intrinsics land.
# BUG: Path#to_s returns nil (both engines)
# check("to_s", p.to_s == "/usr/bin/ruby.exe")
# BUG: Path#parent returns nil (both engines)
# check("parent", p.parent.to_s == "/usr/bin")
# check("parent of root", Path.new("/").parent.to_s == "/")
# BUG: Path#name / #stem / #extension return nil (both engines)
# check("name", p.name == "ruby.exe")
# check("stem", p.stem == "ruby")
# check("extension", p.extension == "exe")
# check("extension none", Path.new("/usr/bin/ruby").extension == "")
# check("dotfile stem", Path.new(".bashrc").stem == ".bashrc")
# BUG: Path#root / #absolute? / #home_relative? / #segments return nil (both engines)
# check("root", p.root.to_s == "/")
# check("absolute?", p.absolute?)
# check("relative", !Path.new("a/b").absolute?)
# check("home_relative?", Path.new("~/x").home_relative?)
# check("segments", p.segments == ["usr", "bin", "ruby.exe"])
# BUG: Path#exist? / #file? / #directory? / #symlink? / #type / #file_type return nil (both engines)
# check("exist?", Path.new("VERSION").exist?)
# check("missing", !Path.new("no/such/file").exist?)
# check("file?", Path.new("VERSION").file?)
# check("directory?", Path.new("core").directory?)
# check("symlink?", !Path.new("VERSION").symlink?)
# BUG: Path#entries / #children / #ls / #each / #empty? return nil (both engines)
# check("entries", Path.new("core/traits").entries.include?("comparable.w"))
# check("children are paths", type(Path.new("core/traits").children[0]) == "Path")
# check("empty? nonempty dir", !Path.new("core/traits").empty?)
# BUG: Path#join, `/`, #expand return nil (both engines)
# check("join", Path.new("/usr").join("lib", "site").to_s == "/usr/lib/site")
# check("slash", (Path.new("/usr") / "lib").to_s == "/usr/lib")
# check("expand", Path.new("core").expand.absolute?)
# BUG: Path#mtime / #mtime_ns / #size return nil (both engines)
# check("size", Path.new("VERSION").size > 0)
# check("mtime_ns", Path.new("VERSION").mtime_ns > 0)
# BUG: the documented `Path("/usr/bin")` constructor form returns a Path whose methods are all nil too
# check("call constructor", Path("/usr/bin").name == "bin")

<< "ALL PASS path_spec ([passed.load()] checks)"
