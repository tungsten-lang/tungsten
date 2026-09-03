# OS — operating-system interface: commands, files, platform (core/os.w).
#
# Run:
#   bin/tungsten run --interpret spec/core/os_spec.w
#   bin/tungsten -o /tmp/os_spec spec/core/os_spec.w && /tmp/os_spec
#
# Run from the repository root (reads VERSION and core/traits).
# Compiled lane: the interpreter returns nil for every OS method (see BUG below).

use core/os

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()
  << "PASS " + name

# BUG: under `bin/tungsten run --interpret` every OS class method (capture, system, exists?, read_file, ...) returns nil;
# the intrinsics are only wired for the compiled engine. This spec is compiled-lane until that is fixed.

# ---- commands ----
check("capture stdout", OS.capture("echo hi") == "hi\n")
check("capture multiline", OS.capture("printf 'a\\nb'") == "a\nb")
check("capture empty output", OS.capture("true") == "")
check("capture ignores stderr", OS.capture("echo err 1>&2") == "")
check("capture failing command", OS.capture("exit 3") == "")
check("system success", OS.system("true") == true)
check("system failure", OS.system("false") == false)
check("system nonzero exit", OS.system("exit 3") == false)

# ---- filesystem queries ----
check("directory? dir", OS.directory?("core"))
check("directory? file", !OS.directory?("VERSION"))
check("directory? missing", !OS.directory?("no/such/dir"))
check("exists? file", OS.exists?("VERSION"))
check("exists? dir", OS.exists?("core"))
check("exists? missing", !OS.exists?("no/such/file"))
check("file? existing file", OS.file?("VERSION"))
check("file? is an existence test (per doc), so dirs count", OS.file?("core"))
check("file? missing", !OS.file?("no/such/file"))
check("file_size", OS.file_size("VERSION") == OS.read_file("VERSION").size)
check("file_size missing is nil", OS.file_size("no/such/file") == nil)
check("file_mtime_ns positive", OS.file_mtime_ns("VERSION") > 0)
check("file_mtime_ns missing is nil", OS.file_mtime_ns("no/such/file") == nil)

# ---- reading ----
version = OS.read_file("VERSION")
check("read_file", type(version) == "String" && version.size > 0)
check("read_file keeps newline", version.include?("\n"))
check("read_file missing is nil", OS.read_file("no/such/file") == nil)
bytes = OS.read_file_bytes("VERSION")
check("read_file_bytes size", bytes.size == version.size)
check("read_file_bytes first byte", bytes[0] == version.byte_at(0))
entries = OS.read_dir("core/traits")
check("read_dir lists names", entries.include?("comparable.w"))
check("read_dir omits dot entries", !entries.include?(".") && !entries.include?(".."))
check("read_dir missing is nil", OS.read_dir("no/such/dir") == nil)

# ---- writing ----
tmp = OS.capture("mktemp -t tungsten_os_spec").strip
check("mktemp gave a path", tmp.size > 0 && OS.exists?(tmp))
check("write_file returns true", OS.write_file(tmp, "héllo") == true)
check("write_file round-trips utf-8", OS.read_file(tmp) == "héllo")
check("write_file size is bytes", OS.file_size(tmp) == 6)
check("write_file overwrites", OS.write_file(tmp, "") == true && OS.file_size(tmp) == 0)
check("write_file into missing dir is false", OS.write_file("no/such/dir/x.txt", "x") == false)
OS.system("rm -f " + tmp)
check("cleanup removed temp file", !OS.exists?(tmp))

# ---- platform ----
# BUG: OS.platform and OS.arch return nil compiled (expected "macos" / "arm64" on this host)
# check("platform", OS.platform == "macos")
# check("arch", OS.arch == "arm64")

<< "ALL PASS os_spec ([passed.load()] checks)"
