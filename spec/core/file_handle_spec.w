# spec: compiled -- the tree-walker hands a trailing block on any method outside its iterator list to an implicit .each (pre-existing; Tempfile.create's block fails the same way in file_stat_tempfile_spec)
# File.open returns a FileHandle (core/file.w) on every engine. Compiled code
# used to die with "undefined method 'file_open' for File" (2026-10-21): only
# the Ruby implementation had a file_open builtin, so only it could stream a
# file. FileHandle now wraps the runtime's stdio primitives, which the
# tree-walking interpreter forwards and the Ruby implementation shims.

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

tmp = Tempfile.new("tungsten-file-handle")
path = tmp.path
tmp.close!()

# Write mode, incrementally.
f = File.open(path, "w")
check("write returns bytes", f.write("hello\n"), 6)
f.write("big ")
check("non-text writes its to_s", f.write(42), 2)
f.puts("")
f.puts("x")
f.puts()
check("not closed yet", f.closed?(), false)
f.close
check("closed", f.closed?(), true)
check("written text", File.read(path), "hello\nbig 42\nx\n\n")

raised = false
begin
  f.write("late")
rescue e
  raised = true
check("write after close raises", raised, true)

# Block form: the value of the block, closed afterwards.
kept = nil
size = File.open(path, "a") -> (h)
  kept = h
  h.puts("tail")
  h.size
check("append size", size, 21)
check("block closes the handle", kept.closed?(), true)

# Read mode.
lines = []
File.open(path) -> (h)
  lines.push(h.gets)
  lines.push(h.read(3))
  check("tell", h.tell, 9)
  h.rewind
  h.seek(6)
  h.each_line -> (line)
    lines.push(line)
  check("eof", h.eof?, true)
  check("read at end", h.read, "")
  check("read(n) at end", h.read(4), nil)
  check("gets at end", h.gets, nil)
check("lines", lines, ["hello", "big", "big 42\n", "x\n", "\n", "tail\n"])

# Metadata delegates to the path.
File.open(path, "r") -> (h)
  check("type", h.type, "file")
  check("path", h.path, path)
  check("mode", h.mode, "r")

# File.write with a mode and a block opens a handle too.
File.write(path, "w") -> (h)
  h.write("over")
check("File.write block", File.read(path), "over")

missing = false
begin
  File.open(path + ".missing/none")
rescue e
  missing = true
check("missing file raises", missing, true)
File.rm(path)
