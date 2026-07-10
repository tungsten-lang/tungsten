# tungsten — The Tungsten language interpreter and compiler
#
# Main CLI entry point, written in Tungsten itself.
# Option parsing is driven by doc/TUNGSTEN.md via Argon (manpage-as-schema).
# No Ruby dependency for doctor / start / new / run / compile / help.

use argon

ROOT = __DIR__ + "/.."
VERSION = read_file(ROOT + "/VERSION").strip()
COPYRIGHT = "tungsten - Copyright (c) 2013–2026 Erik Peterson.\nTungsten is freely available under the MIT License."
COMPILER = ROOT + "/bin/tungsten-compiler"

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

# ---- Helpers ----

-> sh_quote(s)
  "'" + s.gsub("'", "'\\''") + "'"

-> tool_on_path?(name)
  system("command -v " + sh_quote(name) + " > /dev/null 2>&1")

-> color_on?
  if env("NO_COLOR") != nil
    return false
  if env("CLICOLOR_FORCE") != nil
    return true
  # Best-effort: assume TTY when not in CI
  env("CI") == nil

-> c(use_color, code, text)
  if use_color
    return code + text + "\e[0m"
  text

-> exec_compiler(extra_args)
  if !tool_on_path?(COMPILER) && !system("test -x " + sh_quote(COMPILER))
    << "tungsten: bin/tungsten-compiler not found — run `bin/tungsten build` first"
    exit(1)
  cmd = sh_quote(COMPILER)
  i = 0
  while i < extra_args.size
    cmd = cmd + " " + sh_quote(extra_args[i])
    i = i + 1
  if system(cmd)
    exit(0)
  exit(1)

# Legacy bootstrap / unported tools still live in the Ruby driver.
# Only used for developer options (--ruby/--spinel bootstrap) and
# tools not yet reimplemented in Tungsten (fmt, forge, flame, bit, …).
-> exec_ruby_driver
  ruby_cli = ROOT + "/bin/tungsten.rb"
  ruby = "ruby"
  custom = ROOT + "/src/patched/ruby/ruby"
  if system("test -x " + sh_quote(custom))
    ruby = custom
  cmd = sh_quote(ruby) + " " + sh_quote(ruby_cli)
  args = argv()
  i = 0
  while i < args.size
    cmd = cmd + " " + sh_quote(args[i])
    i = i + 1
  if system(cmd)
    exit(0)
  exit(1)

# ---- doctor ----

-> doctor_check(name, detail, ok, passed, failed, use_color)
  if ok
    passed[0] = passed[0] + 1
    line = "  " + c(use_color, "\e[32m", "✓") + " " + name
    if detail != nil && detail != ""
      line = line + " " + c(use_color, "\e[36m", detail)
    << line
  else
    failed[0] = failed[0] + 1
    line = "  " + c(use_color, "\e[91m", "✗") + " " + name
    if detail != nil && detail != ""
      line = line + " " + c(use_color, "\e[2m", detail)
    << line

-> run_doctor
  use_color = color_on?()
  << c(use_color, "\e[1m\e[33m", "✶ Tungsten Doctor")
  << ""

  passed = [0]
  failed = [0]

  ver = VERSION
  doctor_check("Tungsten", ver, true, passed, failed, use_color)

  has_compiler = system("test -x " + sh_quote(COMPILER))
  doctor_check("Compiler", has_compiler ? COMPILER : "not built — run bin/tungsten build", has_compiler, passed, failed, use_color)

  has_clang = tool_on_path?("clang")
  clang_ver = ""
  if has_clang
    clang_ver = capture("clang --version 2>/dev/null | head -1").strip()
  doctor_check("clang", clang_ver != "" ? clang_ver : "not found", has_clang, passed, failed, use_color)

  has_make = tool_on_path?("make")
  doctor_check("make", has_make ? "ok" : "not found", has_make, passed, failed, use_color)

  # Functional lld check: can clang link with -fuse-ld=lld?
  lld_ok = system("printf 'int main(void){return 0;}' | clang -fuse-ld=lld -x c - -o /tmp/tungsten-lld-check-$$ > /dev/null 2>&1 && rm -f /tmp/tungsten-lld-check-$$")
  doctor_check("lld (clang -fuse-ld=lld)", lld_ok ? "ok" : "not found", lld_ok, passed, failed, use_color)

  zstd_ok = system("printf '#include <zstd.h>\\n' | clang -I/opt/homebrew/include $(pkg-config --cflags libzstd 2>/dev/null) -E -x c - > /dev/null 2>&1")
  doctor_check("libzstd (zstd.h)", zstd_ok ? "ok" : "not found", zstd_ok, passed, failed, use_color)

  # Optional / developer
  << ""
  << c(use_color, "\e[2m", "Developer options (not required for normal use):")
  has_ruby = tool_on_path?("ruby")
  ruby_detail = has_ruby ? capture("ruby -v 2>/dev/null").strip() : "not installed"
  doctor_check("Ruby (--ruby bootstrap)", ruby_detail, true, passed, failed, use_color)

  has_nvcc = tool_on_path?("nvcc")
  doctor_check("nvcc (CUDA)", has_nvcc ? capture("nvcc --version 2>/dev/null | tail -1").strip() : "not installed", true, passed, failed, use_color)

  has_metal = system("command -v xcrun > /dev/null 2>&1 && xcrun -f metal > /dev/null 2>&1")
  doctor_check("Metal toolchain", has_metal ? "ok" : "not on this host", true, passed, failed, use_color)

  << ""
  total = passed[0] + failed[0]
  << c(use_color, "\e[2m", "" + passed[0].to_s() + "/" + total.to_s() + " required checks passed")
  if failed[0] > 0
    exit(1)
  exit(0)

# ---- start ----

-> run_start(args)
  use_color = color_on?()
  agent = false
  i = 0
  while i < args.size
    if args[i] == "--agent"
      agent = true
    i = i + 1

  if agent
    primer = ROOT + "/doc/TUNGSTEN_FOR_LLMS.md"
    if system("test -f " + sh_quote(primer))
      << read_file(primer)
    << ""
    << "More for agents:"
    << "  stdlib index:  " + ROOT + "/doc/CORE.md"
    << "  getting started: " + ROOT + "/doc/getting-started/"
    << "  examples:      " + ROOT + "/doc/examples"
    << "  web index:     https://tungsten-lang.org/llms.txt"
    exit(0)

  << ""
  << c(use_color, "\e[1m\e[36m", "The Tungsten Programming Language")
  << ""
  << "An object-oriented, multi-paradigm systems programming language"
  << ""
  << c(use_color, "\e[1m", "The map")
  << ""
  << "  tungsten " + c(use_color, "\e[33m", "run") + "     FILE.w   run a Tungsten program"
  << "  tungsten " + c(use_color, "\e[33m", "compile") + " FILE.w   compile a Tungsten program"
  << ""
  << "  tungsten " + c(use_color, "\e[33m", "build") + "            build the self-hosted compiler"
  << "  tungsten " + c(use_color, "\e[33m", "doctor") + "           diagnose environment issues"
  << ""
  << "  tungsten " + c(use_color, "\e[33m", "console") + "         interactive playground (also: wit)"
  << ""
  << "  " + c(use_color, "\e[32m", "Spec") + "                      doc/specification"
  << "  " + c(use_color, "\e[32m", "Getting started") + "           doc/getting-started"
  << "  " + c(use_color, "\e[32m", "Examples") + "                  doc/examples"
  << ""
  << c(use_color, "\e[1m", "Try it now")
  << ""
  << "  " + c(use_color, "\e[32m", "bin/tungsten -e '<< 1 + 1'") + "   " + c(use_color, "\e[2m", "#=> 2")
  << ""

  has_compiler = system("test -x " + sh_quote(COMPILER))
  if has_compiler
    << c(use_color, "\e[1m", "Next")
    << ""
    << "  " + c(use_color, "\e[32m", "tungsten console") + "    or: wit"
  else
    << c(use_color, "\e[1m", "Next — build the compiler") + " " + c(use_color, "\e[2m", "(a fresh clone ships without one)")
    << ""
    << "  " + c(use_color, "\e[32m", "bin/tungsten build")
    << "  " + c(use_color, "\e[2m", "or one-line install:") + " " + c(use_color, "\e[32m", "curl -fsSL tungsten-lang.org/install | sh")
  << ""
  exit(0)

# ---- new ----

-> run_new(args)
  if args.size == 0
    << "Usage: tungsten new <project-name>"
    exit(1)
  name = args[0]
  if system("test -e " + sh_quote(name))
    << "tungsten new: `" + name + "` already exists"
    exit(1)
  if !system("mkdir " + sh_quote(name))
    << "tungsten new: could not create directory `" + name + "`"
    exit(1)
  write_file(name + "/main.w", "<< \"hello world\"\n")
  use_color = color_on?()
  << c(use_color, "\e[1m\e[33m", "✶ Created " + name + "/")
  << "  " + c(use_color, "\e[2m", "main.w")
  << ""
  << c(use_color, "\e[32m", "Run: cd " + name + " && tungsten main.w")
  exit(0)

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

# Developer option: force the Ruby tree-walking interpreter.
if opts.flag?("ruby")
  exec_ruby_driver()

command = opts.command()
rest = opts.arguments()

case command
when "compile", "compile-batch"
  # Forward remaining argv to the compiled compiler.
  args = argv()
  # Drop the leading command token so compiler sees flags + file.
  forwarded = []
  i = 0
  while i < args.size
    if i == 0 && (args[i] == "compile" || args[i] == "compile-batch")
      forwarded.push(args[i])
    elsif i > 0
      forwarded.push(args[i])
    i = i + 1
  if forwarded.size == 0
    forwarded = ["compile"]
  exec_compiler(forwarded)

when "run"
  args = argv()
  forwarded = ["run"]
  i = 0
  while i < args.size
    if !(i == 0 && args[i] == "run")
      forwarded.push(args[i])
    i = i + 1
  exec_compiler(forwarded)

when "build"
  # Bootstrap driver still lives in bin/commands/build.rb until the
  # full build graph is ported. Default path uses the C VM (no --ruby).
  # --ruby / --spinel are developer options (see manpage).
  exec_ruby_driver()

when "fmt"
  exec_ruby_driver()

when "new"
  run_new(rest)

when "start"
  run_start(rest)

when "doctor"
  run_doctor()

when "ai", "symbolicate", "forge", "flame", "fire"
  exec_ruby_driver()

when "console"
  # Public REPL entry (alongside bin/wit). Compiler uses --repl internally.
  exec_compiler(["--repl"])

when "repl"
  << "tungsten: use `bin/wit` or `bin/tungsten console` for the REPL"
  exit(2)

when "bit"
  exec_ruby_driver()

when nil
  # Bare invocation: file args or help
  args = opts.args()
  if args.size > 0
    # First arg may be a .w file → run it
    first = args[0]
    if first.ends_with?(".w") || system("test -f " + sh_quote(first))
      forwarded = ["run"]
      i = 0
      while i < args.size
        forwarded.push(args[i])
        i = i + 1
      exec_compiler(forwarded)
    # Unknown subcommand — try as file, else help
    exec_compiler(["run", first])
  else
    opts.help!
else
  # Unknown command name: treat as a source file path
  forwarded = ["run", command]
  i = 0
  while i < rest.size
    forwarded.push(rest[i])
    i = i + 1
  exec_compiler(forwarded)
