use core/file
-> check(name, value)
  raise "FAIL [name]" if !value
  << "PASS [name]"
root = Tempfile.new("file-paths-links")
base = root.path
root.close!()
link = base + ".link"
begin
  File.write(base, "target")
  File.symlink(base, link)
  check("symlink target", File.readlink(link) == base)
  check("expand_path preserves link name", File.expand_path(link) == link)
  check("expand_path dot components", File.expand_path("a/../b", "/tmp") == "/tmp/b")
  check("realpath follows link", File.realpath(link) == File.realpath(base))
  check("basename", File.basename("/a/b/") == "b")
  check("dirname", File.dirname("/a/b/") == "/a")
  check("relative dirname", File.dirname("file") == ".")
  check("extension", File.extname("/a/file.mov") == ".mov")
  check("trailing slash extension", File.extname("/a/file.mov/") == ".mov")
  check("leading dots extension", File.extname("..hidden") == "" && File.extname("...") == "")
  check("dotfile extension", File.extname(".hidden") == "")
ensure
  File.unlink(link) if File.symlink?(link)
  File.unlink(base) if File.exist?(base)
