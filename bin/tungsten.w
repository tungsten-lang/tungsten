# tungsten — The Tungsten language interpreter and compiler
#
# This is the main CLI entry point, written in Tungsten itself.
# Option parsing is driven by doc/TUNGSTEN.md via Argon.

use argon

ROOT = __DIR__ + "/.."
VERSION = read_file(ROOT + "/VERSION").strip()
COPYRIGHT = "tungsten - Copyright (c) 2013–2026 Erik Peterson.\nTungsten is freely available under the MIT License."

# Read the manpage from doc/TUNGSTEN.md, strip the markdown fences
manpage_raw = read_file(ROOT + "/doc/TUNGSTEN.md")
lines = manpage_raw.split("\n")
manpage_lines = []
in_fence = false
i = 0
while i < lines.size
  line = lines[i]
  if line.starts_with?("```")
    in_fence = !in_fence
    i = i + 1
    next
  if in_fence
    manpage_lines.push(line)
  i = i + 1
MANPAGE = manpage_lines.join("\n")

# ---- Helper functions ----

# Wrap one argument in single quotes so paths with spaces (or other shell
# metacharacters) survive being passed through `system`, which takes a single
# shell string. Embedded single quotes are escaped with the POSIX '\'' idiom.
-> sh_quote(s)
  "'" + s.gsub("'", "'\\''") + "'"

# Delegate to bin/tungsten.rb (the Ruby CLI) for commands not yet ported.
# Passes through the original ARGV so the Ruby CLI sees everything, and
# propagates the child's success/failure as this process's exit status —
# otherwise `tungsten broken.w` would report success on a compile error.
-> exec_ruby(command)
  ruby_cli = ROOT + "/bin/tungsten.rb"
  args = argv()
  cmd = "ruby " + sh_quote(ruby_cli)
  i = 0
  while i < args.size
    cmd = cmd + " " + sh_quote(args[i])
    i = i + 1
  if system(cmd)
    exit(0)
  exit(1)

# Run bit subcommands: tungsten bit install, tungsten bit new, etc.
-> run_bit(args)
  ruby_cli = ROOT + "/bin/tungsten.rb"
  cmd = "ruby " + sh_quote(ruby_cli) + " bit"
  i = 0
  while i < args.size
    cmd = cmd + " " + sh_quote(args[i])
    i = i + 1
  if system(cmd)
    exit(0)
  exit(1)

-> start_repl
  repl_source = ROOT + "/compiler/lib/repl.w"
  ruby_cli = ROOT + "/bin/tungsten.rb"
  if system("ruby " + sh_quote(ruby_cli) + " --ruby " + sh_quote(repl_source))
    exit(0)
  exit(1)

# ---- Parse options via Argon ----

cli = Argon.new(MANPAGE)
opts = cli.parse(argv())

# ---- Handle info flags (no file needed) ----

if opts.flag?("version") || opts.flag?("v")
  << "tungsten " + VERSION
  exit(0)

if opts.flag?("copyright")
  << COPYRIGHT
  exit(0)

if opts.flag?("help") || opts.flag?("h")
  opts.help!

if opts.flag?("repl")
  start_repl()
  exit(0)

# ---- Dispatch commands ----

command = opts.command()

# Built-in commands dispatch to the Ruby CLI for now.
# As commands are ported to Tungsten, they move here.

case command
when "compile", "compile-batch"
  exec_ruby("compile")
when "build"
  exec_ruby("build")
when "fmt"
  exec_ruby("fmt")
when "new"
  exec_ruby("new")
when "start"
  exec_ruby("start")
when "doctor"
  exec_ruby("doctor")
when "ai"
  exec_ruby("ai")
when "symbolicate"
  exec_ruby("symbolicate")
when "forge"
  exec_ruby("forge")
when "flame", "fire"
  exec_ruby("flame")
when "repl", "console"
  # `repl` is canonical; `console` is its alias. (In practice the bin/tungsten
  # wrapper routes both to the compiled REPL before this dispatch is reached;
  # this arm covers direct tungsten.wc invocation.)
  start_repl()
  exit(0)
when "bit"
  run_bit(opts.arguments())
when nil
  if opts.args().size > 0
    exec_ruby(nil)
  else
    opts.help!
else
  # Unknown command — might be a filename, pass through to Ruby CLI
  exec_ruby(nil)
