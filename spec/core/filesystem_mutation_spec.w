use core/file

-> check(name, condition)
  if condition
    << "PASS " + name
  else
    << "FAIL " + name

root = Tempfile.new("tungsten-filesystem-mutation")
base = root.path
root.close!()

source = base + ".source"
linked = base + ".linked"
destination = base + ".destination"
atomic = base + ".atomic"

begin
  File.write(source, "hard-link")
  check("chmod", File.chmod(source, 0o640) && File.stat(source).permissions == 0o640)
  check("link", File.link(source, linked) && File.read(linked) == "hard-link")
  check("link.inode", File.stat(source).ino == File.stat(linked).ino)

  File.write(destination, "old")
  File.atomic_replace(source, destination)
  check("replace.content", File.read(destination) == "hard-link")
  check("replace.consumes_source", !File.exist?(source))

  File.write(atomic, "before")
  File.chmod(atomic, 0o640)
  written = File.atomic_write(atomic, "after")
  check("atomic_write.size", written == 5)
  check("atomic_write.content", File.read(atomic) == "after")
  check("atomic_write.permissions", File.stat(atomic).permissions == 0o640)

  fresh = base + ".fresh"
  written = File.atomic_write(fresh, "new")
  check("atomic_write.new", written == 3 && File.read(fresh) == "new")
  check("atomic_write.new_permissions", File.stat(fresh).permissions == 0o600)
  File.unlink(fresh)

  begin
    File.chmod(atomic, 0o10000)
    check("chmod.invalid", false)
  rescue e
    check("chmod.invalid", true)
ensure
  File.unlink(source) if File.exist?(source)
  File.unlink(linked) if File.exist?(linked)
  File.unlink(destination) if File.exist?(destination)
  File.unlink(atomic) if File.exist?(atomic)
