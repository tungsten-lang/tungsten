# tungsten — The Tungsten language interpreter and compiler
#
# Main CLI entry point, written in Tungsten itself.
# Option parsing is driven by doc/TUNGSTEN.md via Argon (manpage-as-schema).
# No Ruby dependency for doctor / start / new / run / compile / help.

use argon

ROOT = __DIR__ + "/.."
VERSION = read_file(ROOT + "/VERSION").strip
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

# Legacy bootstrap only: --ruby / --spinel / `build` still use the Ruby driver.
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

# Compile-on-demand a bin/commands/*.w tool, then exec it with tool_args.
# Interpretation is intentionally avoided: several stdlib methods (and JSON
# edge cases) behave better on the compiled path.
-> run_command_w(rel_path, tool_args)
  if !system("test -x " + sh_quote(COMPILER))
    << "tungsten: bin/tungsten-compiler not found — run `bin/tungsten build` first"
    exit(1)
  entry = ROOT + "/" + rel_path
  # Cache native binaries next to the source: bin/commands/fmt.w → bin/commands/fmt
  out_bin = entry.replace(".w", "")
  need = true
  if system("test -x " + sh_quote(out_bin))
    if system("test " + sh_quote(entry) + " -ot " + sh_quote(out_bin))
      need = false
  if need
    cmd = "BIT_HOME=" + sh_quote(ROOT + "/bits") + " TUNGSTEN_ROOT=" + sh_quote(ROOT) + " " + sh_quote(COMPILER) + " compile " + sh_quote(entry) + " --out " + sh_quote(out_bin) + " --no-lto"
    if !system(cmd + " >/dev/null 2>&1")
      << "tungsten: failed to compile " + rel_path
      exit(1)
    if system("uname -s | grep -q Darwin")
      system("codesign --force -s - " + sh_quote(out_bin) + " >/dev/null 2>&1")
  cmd = "BIT_HOME=" + sh_quote(ROOT + "/bits") + " TUNGSTEN_ROOT=" + sh_quote(ROOT) + " " + sh_quote(out_bin)
  i = 0
  while i < tool_args.size
    cmd = cmd + " " + sh_quote(tool_args[i])
    i = i + 1
  if system(cmd)
    exit(0)
  exit(1)

# Compile-on-demand a bit entry (flame/bit use `module` etc. the interpreter
# does not support — they must be native binaries).
-> ensure_bit_binary(bit_pkg, entry_name)
  bin_dir = ROOT + "/bits/" + bit_pkg + "/bin"
  out_bin = bin_dir + "/" + entry_name
  src = ROOT + "/bits/" + bit_pkg + "/lib/" + entry_name + ".w"
  if !system("test -f " + sh_quote(src))
    << "tungsten: missing " + src
    exit(1)
  # Rebuild if missing or source newer than binary
  need = true
  if system("test -x " + sh_quote(out_bin))
    if system("test " + sh_quote(src) + " -ot " + sh_quote(out_bin))
      need = false
  if need
    system("mkdir -p " + sh_quote(bin_dir))
    cmd = "BIT_HOME=" + sh_quote(ROOT + "/bits") + " TUNGSTEN_ROOT=" + sh_quote(ROOT) + " " + sh_quote(COMPILER) + " compile " + sh_quote(src) + " --out " + sh_quote(out_bin) + " --no-lto"
    if !system(cmd + " >/dev/null 2>&1")
      << "tungsten: failed to compile " + bit_pkg + " (" + entry_name + ")"
      << "  try: BIT_HOME=bits bin/tungsten-compiler compile " + src + " --out " + out_bin
      exit(1)
    if system("uname -s | grep -q Darwin")
      system("codesign --force -s - " + sh_quote(out_bin) + " >/dev/null 2>&1")
  out_bin

-> run_bit_binary(bit_pkg, entry_name, tool_args)
  out_bin = ensure_bit_binary(bit_pkg, entry_name)
  cmd = "BIT_HOME=" + sh_quote(ROOT + "/bits") + " TUNGSTEN_ROOT=" + sh_quote(ROOT) + " " + sh_quote(out_bin)
  i = 0
  while i < tool_args.size
    cmd = cmd + " " + sh_quote(tool_args[i])
    i = i + 1
  if system(cmd)
    exit(0)
  exit(1)

# Args after the subcommand token (so flags like -w still reach the tool).
-> tool_argv_after_command(command_name)
  raw = argv()
  out = []
  i = 0
  while i < raw.size
    if raw[i] == command_name
      i = i + 1
      while i < raw.size
        out.push(raw[i])
        i = i + 1
      return out
    i = i + 1
  # Command name not found as a bare token — drop first arg if present
  i = 1
  while i < raw.size
    out.push(raw[i])
    i = i + 1
  out

# ---- doctor / bootstrap (bash; work without a compiler) ----

-> run_doctor
  if system("bash " + sh_quote(ROOT + "/bin/commands/doctor.sh"))
    exit(0)
  exit(1)

-> run_bootstrap(tool_args)
  cmd = "bash " + sh_quote(ROOT + "/bin/commands/bootstrap.sh")
  i = 0
  while i < tool_args.size
    cmd = cmd + " " + sh_quote(tool_args[i])
    i = i + 1
  if system(cmd)
    exit(0)
  exit(1)

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
  << "  tungsten " + c(use_color, "\e[33m", "bootstrap") + "       stage-1 compiler (no Ruby; bash)"
  << "  tungsten " + c(use_color, "\e[33m", "build") + "            full self-host (stage1+stage2 + bits)"
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
    << c(use_color, "\e[1m", "Next — bootstrap the compiler") + " " + c(use_color, "\e[2m", "(a fresh clone ships without one)")
    << ""
    << "  " + c(use_color, "\e[32m", "bin/tungsten bootstrap") + "  " + c(use_color, "\e[2m", "# stage 1, no Ruby")
    << "  " + c(use_color, "\e[32m", "bin/tungsten build") + "      " + c(use_color, "\e[2m", "# full self-host + bits")
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

command = opts.command
rest = opts.arguments

# Global --help only when no subcommand (so `tungsten forge --help` reaches forge).
if (opts.flag?("help") || opts.flag?("h")) && command == nil
  opts.help!

# Developer option: force the Ruby tree-walking interpreter.
if opts.flag?("ruby")
  exec_ruby_driver()

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
  run_command_w("bin/commands/fmt.w", tool_argv_after_command("fmt"))

when "new"
  run_new(rest)

when "start"
  run_start(rest)

when "doctor"
  run_doctor()

when "bootstrap"
  run_bootstrap(tool_argv_after_command("bootstrap"))

when "ai"
  run_command_w("bin/commands/ai.w", tool_argv_after_command("ai"))

when "symbolicate"
  run_command_w("bin/commands/symbolicate.w", tool_argv_after_command("symbolicate"))

when "forge"
  run_command_w("bin/commands/forge.w", tool_argv_after_command("forge"))

when "flame", "fire"
  run_bit_binary("tungsten-flame", "flame", tool_argv_after_command(command))

when "console"
  # Public REPL entry (alongside bin/wit). Compiler uses --repl internally.
  exec_compiler(["--repl"])

when "repl"
  << "tungsten: use `bin/wit` or `bin/tungsten console` for the REPL"
  exit(2)

when "bit"
  run_bit_binary("tungsten-bit", "bit", tool_argv_after_command("bit"))

when nil
  # Bare invocation: file args or help
  args = opts.args
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
