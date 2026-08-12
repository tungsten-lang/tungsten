use core/file

-> check(name, condition)
  if condition
    << "PASS " + name
  else
    << "FAIL " + name

tempfile = Tempfile.new("tungsten-file-stat")
path = tempfile.path
check("temp.exists", File.exist?(path))
check("temp.write", tempfile.write("tungsten") == 8)

stat = File.stat(path)
check("stat.present", stat != nil)
check("stat.path", stat.path == path)
check("stat.type", stat.file?() && !stat.directory?() && !stat.symlink?())
check("stat.size", stat.size == 8)
check("temp.size", tempfile.size == 8)
check("stat.permissions", stat.permissions == 0o600)
check("stat.times", stat.atime_ns > 0 && stat.mtime_ns > 0 && stat.ctime_ns > 0)
check("stat.blocks", stat.blksize > 0 && stat.blocks >= 0)

lstat = File.lstat(path)
check("lstat.regular", lstat != nil && lstat.file?())
check("stat.missing", File.stat(path + ".missing") == nil)

spec_root = File.expand_path("spec")
check("expand_path.base", File.expand_path("compiler", spec_root) == File.expand_path("spec/compiler"))

tempfile.close!()
check("temp.close_bang", tempfile.closed?() && !File.exist?(path))
begin
  tempfile.read()
  check("temp.closed_read", false)
rescue e
  check("temp.closed_read", e.to_s().include?("closed tempfile"))

scoped_path = nil
Tempfile.create("tungsten-file-scoped") -> (scoped)
  scoped_path = scoped.path
  scoped.write("scope")
  check("scoped.inside", File.exist?(scoped_path))
check("scoped.cleanup", !File.exist?(scoped_path))

raised_path = nil
begin
  Tempfile.create("tungsten-file-raised") -> (scoped)
    raised_path = scoped.path
    raise "expected"
rescue e
  check("scoped.raise", e.to_s().include?("expected"))
check("scoped.raise_cleanup", !File.exist?(raised_path))
