# `tungsten sandbox FILE.w [args...]` — compile a program and run it with the
# runtime sandbox gate latched.
#
# Inside the sandbox, file IO, sockets, process control, and environment access
# are blocked (a catchable error) or stubbed (a benign value), and every attempt
# is logged as one JSON line to TUNGSTEN_SANDBOX_LOG, or stderr by default:
#
#   {"sandbox":"block","op":"read_file","detail":"/etc/passwd"}
#
# See core/sandbox.w for the op list, and services/api/ for the HTTP service
# built on the same gate.
#
# The child inherits this process's environment, so the gate is latched with
# setenv rather than by wrapping the program in a shell — which keeps the
# program's own arguments off any command line, where quoting could mangle them.
#
# Exit status is the sandboxed program's own, unchanged: callers distinguish
# `exit 3` from a crash, and the execution API depends on it.

-> usage
  << "Usage: tungsten sandbox FILE.w \[args...\]"
  << ""
  << "  Compile FILE.w, then run it with the runtime sandbox latched:"
  << "  file IO, sockets, process control, and environment access are"
  << "  stubbed or blocked; every attempt is logged as a JSON line."
  << ""
  << "  --log PATH   append the attempt log to PATH instead of stderr"
  << "               (same as TUNGSTEN_SANDBOX_LOG=PATH)"

-> shq(s)
  "'" + s.gsub("'", "'\\''") + "'"

-> tungsten_root
  root = env("TUNGSTEN_ROOT")
  if root == nil || root == ""
    root = env("HOME") + "/.tungsten"
  root

args = argv()

log_path = ""
source = nil
program_args = []

i = 0
while i < args.size
  a = args[i]
  if source != nil
    # Everything after the source file belongs to the program, untouched.
    program_args.push(a)
  elsif a == "--log"
    i = i + 1
    if i < args.size
      log_path = args[i]
  elsif a.starts_with?("--log=")
    log_path = a.slice(6, a.size())
  elsif a == "-h" || a == "--help"
    usage
    exit 0
  else
    source = a
  i = i + 1

if source == nil
  eprint("tungsten sandbox: source file required — tungsten sandbox FILE.w \[args...\]\n")
  exit 2

unless File.exist?(source)
  eprint("tungsten sandbox: no such file: " + source + "\n")
  exit 2

compiler = tungsten_root + "/bin/tungsten-compiler"
unless File.exist?(compiler)
  eprint("tungsten sandbox: build the compiler first — bin/tungsten build\n")
  exit 1

work = ccall("__w_mkdtemp", "tungsten-sandbox")
binary = work + "/program"

# Compile quietly: stdout carries only "Built <path>", which is noise here,
# while stderr keeps diagnostics flowing to the terminal as they happen.
build_cmd = shq(compiler) + " compile " + shq(source) + " --out " + shq(binary) + " --no-lto > /dev/null"
build_argv = []
build_argv.push("/bin/sh")
build_argv.push("-c")
build_argv.push(build_cmd)
builder = Process.spawn(build_argv)
build_status = builder.wait

if build_status != 0 || !File.exist?(binary)
  OS.system("rm -rf " + shq(work))
  eprint("tungsten sandbox: compile failed for " + source + "\n")
  if build_status == 0
    exit 1
  exit build_status

# macOS refuses to launch a freshly linked binary unsigned. Allowed to fail:
# on Linux codesign is simply absent.
OS.system("codesign --force -s - " + shq(binary) + " >/dev/null 2>&1 || true")

# Latch the gate for the child through the inherited environment.
ccall("w_setenv", "TUNGSTEN_SANDBOX", "1")
if log_path != ""
  ccall("w_setenv", "TUNGSTEN_SANDBOX_LOG", log_path)

run_argv = []
run_argv.push(binary)
j = 0
while j < program_args.size
  run_argv.push(program_args[j])
  j = j + 1

child = Process.spawn(run_argv)
code = child.wait
OS.system("rm -rf " + shq(work))
exit code
