# tungsten build — self-host build orchestrator.
#
# Port of bin/commands/build.rb (Ruby) to Tungsten. Runs as a compiled
# binary (bin/commands/build), exec'd by bin/tungsten's `build` arm and by
# bin/commands/bootstrap.sh's chain step. Compiled-only: Process.spawn and
# the w_setenv/__w_mkdir_p externs are not in the interpreter whitelist.
#
# Pipeline: preflight -> runtime archive -> stage 0 (C VM) -> stage 1 ->
# stage 2 -> byte-identity verify (stage1 .ll == stage2 .ll) -> install
# through the content-addressed signed cache -> release artifacts -> bits.
#
# Cache-key structure mirrors build.rb exactly; per-file digests are
# SHA-256 via the native crypto extern (fast enough to skip build.rb's
# persistent digest cache entirely). Key VALUES still differ from the
# Ruby driver's (joiners/tree-walk order), so the first build after the
# migration is cold. build/cache layout and artifact names are unchanged.

# ── Constants ───────────────────────────────────────────────────

ROOT = File.expand_path(env("TUNGSTEN_ROOT") != nil && env("TUNGSTEN_ROOT") != "" ? env("TUNGSTEN_ROOT") : __DIR__ + "/../..")
COMPILER_BIN = ROOT + "/bin/tungsten-compiler"
RUNTIME_DIR = ROOT + "/runtime"
GEM_EXE = ROOT + "/implementations/ruby/exe/ruby-tungsten"
CUSTOM_RUBY = ROOT + "/src/patched/ruby/ruby"
C_INTERP = ROOT + "/implementations/c/build/tungsten-c"
C_INTERP_DIR = ROOT + "/implementations/c"
SPINEL_BIN = ROOT + "/src/patched/spinel/spinel"
SPINEL_RUNTIME = ROOT + "/src/patched/spinel/lib/libspinel_rt.a"
BUILD_CACHE_DIR = ROOT + "/build/cache"

# ── Small helpers ───────────────────────────────────────────────

-> shq(s)
  "'" + s.gsub("'", "'\\''") + "'"

build_homebrew_prefix_memo = {}

-> build_homebrew_prefix(formula)
  key = formula == "" ? :root : formula.to_sym()
  cached = build_homebrew_prefix_memo[key]
  if cached != nil
    return cached
  cmd = "brew --prefix"
  if formula != ""
    cmd = cmd + " " + shq(formula)
  prefix = capture(cmd + " 2>/dev/null").strip
  build_homebrew_prefix_memo[key] = prefix
  prefix

# substring test via slice scan — portable across core versions (contains?
# is a recent alias; a fresh stage-1 compiler may carry an older core).
-> str_has?(s, sub)
  if sub.size == 0
    return true
  limit = s.size - sub.size
  i = 0
  while i <= limit
    if s.slice(i, sub.size) == sub
      return true
    i = i + 1
  false

-> eputs(msg)
  ccall("w_eputs", msg)

# /bin/sh -c with the child's real exit status.
-> sh(cmd)
  a = []
  a.push("/bin/sh")
  a.push("-c")
  a.push(cmd)
  Process.spawn(a).wait

-> sh_ok(cmd)
  sh(cmd) == 0

# Named make_dirs, NOT mkdir_p: top-level fns compile under `__w_<name>`
# (the seam namespace that lets source fns override weak runtime
# defaults), so a fn named mkdir_p wrapping ccall("__w_mkdir_p") binds
# the ccall to itself. The compiler diagnoses that self-binding now
# (lowering/calls.w); the rename here is the by-design resolution.
-> make_dirs(path)
  ccall("__w_mkdir_p", path)

-> executable?(path)
  system("test -x " + shq(path) + " -a ! -d " + shq(path))

-> regular_file?(path)
  system("test -f " + shq(path))

-> pid_string
  capture("/bin/sh -c 'echo $PPID'").strip

# SHA-256 over the file bytes (native w_crypto_sha256_hex; binary-safe,
# deterministic across processes — Digest.*64 wyhash is not usable here).
-> file_sha(path)
  bytes = read_file_bytes(path)
  if bytes == nil
    return "missing:" + path
  Digest.sha256(bytes)

-> atomic_copy(src, dst)
  tmp = dst + "." + PID + ".tmp"
  if !sh_ok("cp -p " + shq(src) + " " + shq(tmp) + " && mv -f " + shq(tmp) + " " + shq(dst))
    sh_ok("rm -f " + shq(tmp))
    return false
  true

-> atomic_write(contents, dst)
  tmp = dst + "." + PID + ".tmp"
  if !write_file(tmp, contents)
    return false
  if !sh_ok("mv -f " + shq(tmp) + " " + shq(dst))
    sh_ok("rm -f " + shq(tmp))
    return false
  true

-> same_file_content?(left, right)
  if !regular_file?(left) || !regular_file?(right)
    return false
  if file_size(left) != file_size(right)
    return false
  sh_ok("cmp -s " + shq(left) + " " + shq(right))

-> optional_cache_complete?(path)
  regular_file?(path) || regular_file?(path + ".missing")

-> publish_optional_file(source, cached)
  marker = cached + ".missing"
  if regular_file?(source)
    atomic_copy(source, cached)
    sh_ok("rm -f " + shq(marker))
  else
    tmp = marker + "." + PID + ".tmp"
    write_file(tmp, "missing\n")
    sh_ok("rm -f " + shq(cached) + " && mv -f " + shq(tmp) + " " + shq(marker))

-> restore_optional_file(cached, destination)
  if regular_file?(cached)
    atomic_copy(cached, destination)
  else
    sh_ok("rm -f " + shq(destination))

-> resolve_executable(command)
  if str_has?(command, "/")
    return command
  path_env = env("PATH")
  if path_env == nil
    return command
  dirs = path_env.split(":")
  i = 0
  while i < dirs.size
    candidate = dirs[i] + "/" + command
    if executable?(candidate)
      return candidate
    i = i + 1
  command

-> sibling_tool(command, tool)
  resolved = resolve_executable(command)
  slash = last_slash(resolved)
  if slash < 0
    return nil
  candidate = resolved.slice(0, slash) + "/" + tool
  if executable?(candidate)
    return candidate
  nil

-> last_slash(s)
  i = s.size - 1
  while i >= 0
    if s.slice(i, 1) == "/"
      return i
    i = i - 1
  -1

-> dirname_of(path)
  slash = last_slash(path)
  if slash < 0
    return "."
  if slash == 0
    return "/"
  path.slice(0, slash)

-> basename_of(path)
  slash = last_slash(path)
  path.slice(slash + 1, path.size - slash - 1)

# "path:size:mtime_ns" identity for a tool binary (build.rb tool_identity).
-> tool_identity(command)
  resolved = resolve_executable(command)
  size = file_size(resolved)
  mtime = file_mtime_ns(resolved)
  if size == nil || mtime == nil
    return resolved
  resolved + ":" + size.to_s + ":" + mtime.to_s

-> env_or_empty(name)
  v = env(name)
  if v == nil
    return ""
  v

-> split_ws(s)
  parts = s.split(" ")
  out = []
  i = 0
  while i < parts.size
    p = parts[i].strip
    if p != ""
      out.push(p)
    i = i + 1
  out

-> array_contains?(arr, value)
  i = 0
  while i < arr.size
    if arr[i] == value
      return true
    i = i + 1
  false

-> uniq_strings(arr)
  out = []
  i = 0
  while i < arr.size
    if !array_contains?(out, arr[i])
      out.push(arr[i])
    i = i + 1
  out

-> join_tab(arr)
  arr.join("\t")

-> ms(millis)
  millis.to_s + "ms"

-> rj(s, w)
  out = "" + s
  while out.size < w
    out = " " + out
  out

-> aligned_ms(millis)
  rj(ms(millis), 6)

-> project_relative_path(path)
  prefix = ROOT + "/"
  if path.starts_with?(prefix)
    return path.slice(prefix.size, path.size - prefix.size)
  path

# Env pair lists ride as parallel arrays; construction order is fixed, so
# the joined identity string is deterministic without sorting.
-> env_prefix(keys, vals)
  out = ""
  i = 0
  while i < keys.size
    out = out + keys[i] + "=" + shq(vals[i]) + " "
    i = i + 1
  out

-> env_kv_join(keys, vals)
  parts = []
  i = 0
  while i < keys.size
    parts.push(keys[i] + "=" + vals[i])
    i = i + 1
  join_tab(parts)

# ── Color / output ──────────────────────────────────────────────

-> color_on?
  if env("NO_COLOR") != nil
    return false
  if env("CLICOLOR_FORCE") != nil
    return true
  env("CI") == nil

PID = pid_string()
USE_COLOR = color_on?()
BOLD = USE_COLOR ? "\e[1m" : ""
DIM = USE_COLOR ? "\e[2m" : ""
GREEN = USE_COLOR ? "\e[32m" : ""
RED = USE_COLOR ? "\e[31m" : ""
BRIGHT_RED = USE_COLOR ? "\e[91m" : ""
RESET = USE_COLOR ? "\e[0m" : ""

# ── build_flags port (CPU resolution + ~/.tungsten/config) ─────

-> cpu_alias(value)
  if value == "v1"
    return "x86-64-v1"
  if value == "v2"
    return "x86-64-v2"
  if value == "v3"
    return "x86-64-v3"
  if value == "v4"
    return "x86-64-v4"
  value

-> valid_cpu_char?(c, first)
  if c >= "a" && c <= "z"
    return true
  if c >= "0" && c <= "9"
    return true
  if first
    return false
  c == "_" || c == "." || c == "+" || c == "-"

# Returns the normalized name, or nil on an invalid name (caller dies).
-> normalize_cpu(cpu)
  value = cpu.strip.downcase
  value = cpu_alias(value)
  if value == ""
    return nil
  i = 0
  while i < value.size
    if !valid_cpu_char?(value.slice(i, 1), i == 0)
      return nil
    i = i + 1
  value

-> strip_config_comment(line)
  # strip trailing "  # ..." / "  ; ..." comments
  i = 0
  while i < line.size
    c = line.slice(i, 1)
    if (c == "#" || c == ";") && i > 0
      prev = line.slice(i - 1, 1)
      if prev == " " || prev == "\t"
        return line.slice(0, i)
    i = i + 1
  line

-> configured_value(key)
  path = env_or_empty("TUNGSTEN_CONFIG")
  if path == ""
    home = env_or_empty("HOME")
    path = home + "/.tungsten/config"
  text = read_file(path)
  if text == nil
    return nil
  section = ""
  lines = text.split("\n")
  i = 0
  while i < lines.size
    line = strip_config_comment(lines[i]).strip
    if line != "" && !line.starts_with?("#") && !line.starts_with?(";")
      if line.starts_with?("[") && line.ends_with?("]")
        section = line.slice(1, line.size - 2).strip
      elsif section == "build" && line.starts_with?(key)
        rest = line.slice(key.size, line.size - key.size).strip
        if rest.starts_with?("=")
          value = rest.slice(1, rest.size - 1).strip
          if value.size >= 2
            f = value.slice(0, 1)
            l = value.slice(value.size - 1, 1)
            if (f == "\"" && l == "\"") || (f == "'" && l == "'")
              value = value.slice(1, value.size - 2)
          return value
    i = i + 1
  nil

-> configured_cpu
  from_env = env_or_empty("TUNGSTEN_CPU").strip
  if from_env != ""
    return normalize_cpu(from_env)
  value = configured_value("cpu")
  if value == nil
    return nil
  normalize_cpu(value)

-> host_is_x86?
  m = capture("uname -m").strip
  m == "x86_64" || m == "amd64" || m == "i386" || m == "i486" || m == "i586" || m == "i686"

-> x86_target?(target)
  if target == ""
    return host_is_x86?()
  target.starts_with?("x86_64") || target.starts_with?("amd64")

-> march(cpu, target)
  out = []
  if cpu.starts_with?("x86-64-v") && cpu.size == 9
    out.push("-march=" + cpu)
    out.push("-mtune=generic")
  elsif cpu == "native" && x86_target?(target)
    out.push("-march=native")
    out.push("-mtune=native")
  else
    out.push("-mcpu=" + cpu)
  out

# ── argv parsing (mirrors build.rb order) ───────────────────────

-> die(msg)
  eputs(msg)
  exit(1)

args = argv()

# --compiler-dir NAME (space form only), else TUNGSTEN_COMPILER, else "compiler"
compiler_dir_name = env_or_empty("TUNGSTEN_COMPILER")
if compiler_dir_name == ""
  compiler_dir_name = "compiler"
filtered = []
i = 0
while i < args.size
  if args[i] == "--compiler-dir"
    if i + 1 >= args.size
      die("--compiler-dir requires a value")
    compiler_dir_name = args[i + 1]
    i = i + 2
  else
    filtered.push(args[i])
    i = i + 1
args = filtered

TUNGSTEN_W = ROOT + "/" + compiler_dir_name + "/tungsten.w"

if array_contains?(args, "--help") || array_contains?(args, "-h")
  << "Usage: tungsten build \[options]"
  << ""
  << "Bootstrap the self-hosted Tungsten compiler and build bit entry points."
  << "Default bootstrap: implementations/c (the C bytecode VM)."
  << ""
  << "Options:"
  << "  -1          Build and install only the stage-1 compiler"
  << "  -2          Reuse the existing stage-1 binary and build stage 2"
  << "  --force     Ignore cached stage binaries and rebuild"
  << "  --pgo       Build the compiler with profile-guided optimization"
  << "  --no-bits   Skip compiling bit entry points (implied by -0, -1, and -2)"
  << "  --release   -O3, full LTO, no dev checks, reduced runtime metadata"
  << "  --debug     Include debug symbols, safety checks, and runtime metadata"
  << "  --no-debug  Omit debug symbols and development checks (release default)"
  << "  --cpu CPU   Target CPU (v1/v2/v3/v4/native aliases accepted)"
  << "  --native    Shorthand for --cpu native"
  << "  --target T  Build an artifact for target triple T"
  << "  --portable  Build x86-64-v2 and x86-64-v3 release artifacts"
  << "  --fast      Enable fast, non-IEEE floating-point optimization"
  << "  -h, --help  Show this help"
  << ""
  << "Developer options (bootstrap maintainers; not needed day-to-day):"
  << "  -0          Build only the Spinel stage-0 compiler (implies --spinel)"
  << "  --spinel    Bootstrap stage 1 via Spinel stage-0 instead of the C VM"
  << "  --ruby      Bootstrap stage 1 via the Ruby interpreter"
  << "              (or set TUNGSTEN_BOOTSTRAP=ruby|spinel)"
  exit(0)

# ── Preflight (port of Tungsten::Doctor.build_preflight) ────────

-> preflight_cc
  cc = env_or_empty("TUNGSTEN_CC").strip
  if cc != ""
    return cc
  from_config = configured_value("cc")
  if from_config != nil && from_config != ""
    return from_config
  "clang"

-> tool_on_path?(name)
  if executable?(name)
    return true
  sh_ok("command -v " + shq(name) + " > /dev/null 2>&1")

-> linker_ok?(cc)
  out = "/tmp/tungsten-lld-check-" + PID
  ok = sh_ok("printf 'int main(void){return 0;}' | " + shq(cc) + " -fuse-ld=lld -x c - -o " + shq(out) + " > /dev/null 2>&1")
  sh_ok("rm -f " + shq(out))
  ok

-> header_ok?(name, cflags, cc)
  sh_ok("printf '#include <" + name + ">\\n' | " + shq(cc) + " " + cflags + " -E -x c - > /dev/null 2>&1")

-> cpu_supported?(cpu, cc)
  flags = march(cpu, "")
  out = "/tmp/tungsten-cpu-check-" + PID + ".o"
  ok = sh_ok("printf 'int main(void){return 0;}\\n' | " + shq(cc) + " " + flags.join(" ") + " -x c - -c -o " + shq(out) + " > /dev/null 2>&1")
  sh_ok("rm -f " + shq(out))
  ok

-> zstd_probe_cflags
  out = capture("pkg-config --cflags libzstd 2>/dev/null").strip
  if out != ""
    return out
  prefix = build_homebrew_prefix("")
  if prefix != "" && regular_file?(prefix + "/include/zstd.h")
    return "-I" + prefix + "/include"
  ""

os_name = capture("uname -s").strip
IS_DARWIN = os_name == "Darwin"
IS_LINUX = os_name == "Linux"
PLATFORM = capture("uname -sm").strip

preflight_missing_names = []
preflight_missing_hints = []
pf_cc = preflight_cc()
if !tool_on_path?(pf_cc)
  preflight_missing_names.push("clang")
  preflight_missing_hints.push(IS_LINUX ? "sudo apt-get install clang-22 lld-22" : "brew install llvm lld")
else
  pf_cpu = configured_cpu()
  if pf_cpu == nil
    pf_cpu = "native"
  if !cpu_supported?(pf_cpu, pf_cc)
    preflight_missing_names.push("configured CPU " + pf_cpu)
    preflight_missing_hints.push(IS_LINUX ? "install LLVM/Clang 22+ or choose a supported \[build] cpu" : "brew install llvm; set \[build] cc to $(brew --prefix llvm)/bin/clang")
if !tool_on_path?("make")
  preflight_missing_names.push("make")
  preflight_missing_hints.push(IS_LINUX ? "sudo apt-get install build-essential" : "xcode-select --install")
if !linker_ok?(pf_cc)
  preflight_missing_names.push("lld (clang -fuse-ld=lld)")
  preflight_missing_hints.push(IS_LINUX ? "sudo apt-get install lld-22" : "brew install lld")
if !header_ok?("zstd.h", zstd_probe_cflags(), pf_cc)
  preflight_missing_names.push("libzstd headers (zstd.h)")
  preflight_missing_hints.push(IS_LINUX ? "sudo apt-get install libzstd-dev" : "brew install zstd")

if preflight_missing_names.size > 0
  eputs(BOLD + BRIGHT_RED + "✗ Cannot build — missing required tool(s):" + RESET)
  i = 0
  while i < preflight_missing_names.size
    eputs("  " + BRIGHT_RED + preflight_missing_names[i] + RESET + " — install with:")
    eputs("    " + DIM + preflight_missing_hints[i] + RESET)
    i = i + 1
  eputs("")
  eputs("Then re-run " + BOLD + "bin/tungsten build" + RESET + ". Full check: " + BOLD + "bin/tungsten doctor" + RESET + ".")
  exit(1)

ccall("w_setenv", "TUNGSTEN_CACHE_DIR", BUILD_CACHE_DIR)

# ── Mode flags ──────────────────────────────────────────────────

if array_contains?(args, "--ruby-bootstrap")
  eputs("--ruby-bootstrap has been renamed to --ruby")
  exit(1)

ruby_bootstrap_requested = array_contains?(args, "--ruby") || env_or_empty("TUNGSTEN_BOOTSTRAP") == "ruby"
spinel_requested = array_contains?(args, "--spinel") || env_or_empty("TUNGSTEN_BOOTSTRAP") == "spinel"
stage0_only = array_contains?(args, "-0")
stage1_only = array_contains?(args, "-1")
stage2_only = array_contains?(args, "-2")
pgo_build = array_contains?(args, "--pgo")
force_build = array_contains?(args, "--force")
skip_bits_requested = array_contains?(args, "--no-bits")

# -0 (Spinel stage0) only makes sense in Spinel mode. Auto-promote.
if stage0_only
  spinel_requested = true

spinel_available = executable?(SPINEL_BIN) && regular_file?(SPINEL_RUNTIME)

if ruby_bootstrap_requested && spinel_requested
  eputs("--ruby and --spinel are mutually exclusive — using --spinel")
  ruby_bootstrap_requested = false

if spinel_requested && !spinel_available
  eputs("Spinel not found at " + SPINEL_BIN + " — `--spinel` requested but unavailable. Run `rake deps` to install Spinel.")
  exit(1)

use_spinel_bootstrap = spinel_requested
use_c_bootstrap = !ruby_bootstrap_requested && !spinel_requested

make_dirs(BUILD_CACHE_DIR)
sh_ok("bash " + shq(ROOT + "/bin/commands/cache_gc.sh") + " " + shq(BUILD_CACHE_DIR))

# Per-invocation scratch root (PID-scoped: concurrent builds must not
# clobber each other's in-flight stage output or emitted .ll).
build_scratch_dir = "/tmp/tungsten-build-" + PID
sh_ok("rm -rf " + shq(build_scratch_dir))
make_dirs(build_scratch_dir)

# ── Value flags + validations ───────────────────────────────────

-> take_value_flag(arg_list, name)
  # returns [value_or_nil, remaining_args]; supports --name X and --name=X
  out = []
  value = nil
  prefix = name + "="
  i = 0
  while i < arg_list.size
    a = arg_list[i]
    if value == nil && a.starts_with?(prefix)
      value = a.slice(prefix.size, a.size - prefix.size)
      i = i + 1
    elsif value == nil && a == name
      if i + 1 >= arg_list.size
        eputs(name + " requires a value")
        exit(1)
      value = arg_list[i + 1]
      i = i + 2
    else
      out.push(a)
      i = i + 1
  r = []
  r.push(value)
  r.push(out)
  r

release_mode = array_contains?(args, "--release")
native_mode = array_contains?(args, "--native")
portable_mode = array_contains?(args, "--portable")
debug_requested = array_contains?(args, "--debug")
no_debug_requested = array_contains?(args, "--no-debug")
tv = take_value_flag(args, "--cpu")
cpu_name = tv[0]
args = tv[1]
tv = take_value_flag(args, "--target")
target_triple_opt = tv[0]
args = tv[1]
tv = take_value_flag(args, "--sysroot")
target_sysroot_opt = tv[0]
args = tv[1]
fast_mode = array_contains?(args, "--fast") || array_contains?(args, "-fast")

target_triple = target_triple_opt == nil ? "" : target_triple_opt
target_sysroot = target_sysroot_opt == nil ? "" : target_sysroot_opt

if debug_requested && no_debug_requested
  eputs("--debug and --no-debug are mutually exclusive")
  exit(1)
if portable_mode && (native_mode || cpu_name != nil)
  eputs("--portable selects the x86-64-v2/v3 release set and cannot be combined with --native or --cpu")
  exit(1)
if target_triple != "" && native_mode
  eputs("--target cannot be combined with --native; name a target CPU with --cpu")
  exit(1)
if target_sysroot != "" && target_triple == ""
  eputs("--sysroot requires --target")
  exit(1)
if stage0_only && (portable_mode || target_triple != "")
  eputs("-0 cannot emit release artifacts; build at least stage 1")
  exit(1)

debug_enabled = debug_requested || (!no_debug_requested && !release_mode && !portable_mode)
lto_flag = release_mode ? "-flto=full" : "-flto=thin"

# resolve_cpu(cpu:, native:, configured:) — no target: passed, so a host
# CPU always resolves (build.rb behavior; the cross target is handled by
# blanking cpu/native above the call).
explicit_cpu = nil
if target_triple == "" && cpu_name != nil
  explicit_cpu = normalize_cpu(cpu_name)
  if explicit_cpu == nil
    die("invalid CPU name: " + cpu_name)
if target_triple == "" && native_mode
  if explicit_cpu != nil && explicit_cpu != "native"
    die("--native conflicts with --cpu " + explicit_cpu)
  explicit_cpu = "native"
host_cpu_name = explicit_cpu
if host_cpu_name == nil
  host_cpu_name = configured_cpu()
if host_cpu_name == nil
  host_cpu_name = "native"

march_flags = march(host_cpu_name, "")

# Hand the resolved target to every bootstrap host (the stage-0 C VM
# cannot setenv itself; compiler IR must match the runtime objects).
ccall("w_setenv", "TUNGSTEN_MARCH_ARGS", march_flags.join(" "))

stage_flags = []
if release_mode
  stage_flags.push("--release")
stage_flags.push("--cpu")
stage_flags.push(host_cpu_name)
stage_flags.push(debug_enabled ? "--debug" : "--no-debug")
if fast_mode
  stage_flags.push("--fast")

program_flags = []
if release_mode
  program_flags.push("--release")
program_flags.push("--cpu")
program_flags.push(host_cpu_name)
program_flags.push(debug_enabled ? "--debug" : "--no-debug")
if fast_mode
  program_flags.push("--fast")

-> flags_to_cmd(flags)
  out = ""
  i = 0
  while i < flags.size
    out = out + " " + shq(flags[i])
    i = i + 1
  out

STAGE_FLAGS_CMD = flags_to_cmd(stage_flags)
PROGRAM_FLAGS_CMD = flags_to_cmd(program_flags)

# A fresh-clone bootstrap has already paid for the host runtime, C VM, and
# canonical stage-1 compiler before it can compile this orchestrator. Carry
# those immutable artifacts across the exec boundary so the full build starts
# at stage 2 instead of rebuilding the same three phases. The handoff is
# private to one bootstrap invocation and is accepted only when its profile
# exactly matches this build's resolved host profile.
handoff_path = env_or_empty("TUNGSTEN_BOOTSTRAP_HANDOFF")
handoff_runtime = ""
handoff_stage0 = ""
handoff_stage1 = ""
handoff_stage1_ll = ""
handoff_stage1_sidemap = ""
handoff_profile = host_cpu_name + "|" + (release_mode ? "1" : "0") + "|" + (debug_enabled ? "1" : "0") + "|" + (fast_mode ? "1" : "0") + "|" + (portable_mode ? "1" : "0") + "|" + target_triple
if handoff_path != ""
  if !handoff_path.starts_with?("/")
    handoff_path = ROOT + "/" + handoff_path
  handoff_text = read_file(handoff_path)
  if handoff_text != nil
    handoff_lines = handoff_text.split("\n")
    if handoff_lines.size >= 7 && handoff_lines[0] == "tungsten-bootstrap-handoff-v1" && handoff_lines[1] == handoff_profile
      handoff_stage0 = handoff_lines[2]
      handoff_runtime = handoff_lines[3]
      handoff_stage1 = handoff_lines[4]
      handoff_stage1_ll = handoff_lines[5]
      if handoff_lines[6] != "-"
        handoff_stage1_sidemap = handoff_lines[6]
    else
      eputs(DIM + "ignoring incompatible bootstrap handoff" + RESET)

# ── Toolchain identity material ─────────────────────────────────

-> ambient_toolchain_identity
  keys = []
  keys.push("SDKROOT")
  keys.push("MACOSX_DEPLOYMENT_TARGET")
  keys.push("CPATH")
  keys.push("C_INCLUDE_PATH")
  keys.push("CPLUS_INCLUDE_PATH")
  keys.push("LIBRARY_PATH")
  keys.push("PKG_CONFIG_PATH")
  keys.push("PKG_CONFIG_LIBDIR")
  parts = []
  i = 0
  while i < keys.size
    parts.push(keys[i] + "=" + env_or_empty(keys[i]))
    i = i + 1
  join_tab(parts)

AMBIENT_TOOLCHAIN = ambient_toolchain_identity()

# ── System-dep probes with a marker-fingerprint cache ───────────
# (port of cached_system_deps: one text file per probe under build/cache,
# line 1 = fingerprint, remaining lines = the cached value)

-> marker_fingerprint(marker_paths)
  common = []
  brew = build_homebrew_prefix("")
  if brew != ""
    common.push(brew + "/include")
    common.push(brew + "/lib")
    common.push(brew + "/lib/pkgconfig")
  common.push("/usr/local/include")
  common.push("/usr/local/lib")
  common.push("/usr/local/lib/pkgconfig")
  common.push("/usr/local/share/pkgconfig")
  common.push("/usr/include")
  common.push("/usr/include/zstd.h")
  common.push("/usr/include/oniguruma.h")
  common.push("/usr/lib")
  common.push("/usr/lib/pkgconfig")
  common.push("/usr/share/pkgconfig")
  extra = capture("ls -d /usr/lib/*/pkgconfig /usr/lib/*/pkgconfig/*.pc 2>/dev/null").split("\n")
  i = 0
  while i < extra.size
    if extra[i].strip != ""
      common.push(extra[i].strip)
    i = i + 1
  all = uniq_strings(marker_paths + common)
  parts = []
  i = 0
  while i < all.size
    p = all[i]
    m = file_mtime_ns(p)
    if m == nil
      parts.push(p + ":missing")
    else
      parts.push(p + ":" + m.to_s)
    i = i + 1
  probe_env = "PATH=" + env_or_empty("PATH") + "|PKG_CONFIG_PATH=" + env_or_empty("PKG_CONFIG_PATH") + "|PKG_CONFIG_LIBDIR=" + env_or_empty("PKG_CONFIG_LIBDIR") + "|HOMEBREW_PREFIX=" + env_or_empty("HOMEBREW_PREFIX")
  Digest.sha256(parts.join("|") + "\n" + probe_env + "\n" + tool_identity("pkg-config") + "\n" + tool_identity("brew"))

-> cached_probe_read(name, fingerprint)
  path = BUILD_CACHE_DIR + "/system-deps-" + name + ".txt"
  text = read_file(path)
  if text == nil
    return nil
  lines = text.split("\n")
  if lines.size < 1 || lines[0] != fingerprint
    return nil
  out = []
  i = 1
  while i < lines.size
    out.push(lines[i])
    i = i + 1
  out

-> cached_probe_write(name, fingerprint, value_lines)
  path = BUILD_CACHE_DIR + "/system-deps-" + name + ".txt"
  atomic_write(fingerprint + "\n" + value_lines.join("\n") + "\n", path)

# onig probe: value lines are [cflags, libs] (space-joined)
-> probe_onig
  markers = []
  brew = build_homebrew_prefix("")
  if brew != ""
    markers.push(brew + "/include/oniguruma.h")
    markers.push(brew + "/lib/libonig.dylib")
    markers.push(brew + "/lib/libonig.a")
  fp = marker_fingerprint(markers)
  cached = cached_probe_read("onig", fp)
  if cached != nil && cached.size >= 2
    return cached
  cflags = split_ws(capture("pkg-config --cflags oniguruma 2>/dev/null"))
  libs = split_ws(capture("pkg-config --libs oniguruma 2>/dev/null"))
  if cflags.size == 0 && brew != "" && regular_file?(brew + "/include/oniguruma.h")
    cflags = []
    cflags.push("-I" + brew + "/include")
  if libs.size == 0
    if brew != "" && (regular_file?(brew + "/lib/libonig.dylib") || regular_file?(brew + "/lib/libonig.a"))
      libs = []
      libs.push("-L" + brew + "/lib")
      libs.push("-lonig")
    elsif cflags.size > 0
      libs = []
      libs.push("-lonig")
  if cflags.size > 0
    cflags.push("-DTUNGSTEN_ONIG")
  value = []
  value.push(cflags.join(" "))
  value.push(libs.join(" "))
  cached_probe_write("onig", fp, value)
  value

-> probe_zstd
  markers = []
  brew = build_homebrew_prefix("")
  if brew != ""
    markers.push(brew + "/include/zstd.h")
    markers.push(brew + "/lib/libzstd.dylib")
    markers.push(brew + "/lib/libzstd.a")
  fp = marker_fingerprint(markers)
  cached = cached_probe_read("zstd", fp)
  if cached != nil && cached.size >= 2
    return cached
  cflags = split_ws(capture("pkg-config --cflags libzstd 2>/dev/null"))
  libs = split_ws(capture("pkg-config --libs libzstd 2>/dev/null"))
  if cflags.size == 0 && brew != "" && regular_file?(brew + "/include/zstd.h")
    cflags = []
    cflags.push("-I" + brew + "/include")
  if libs.size == 0
    if brew != "" && (regular_file?(brew + "/lib/libzstd.dylib") || regular_file?(brew + "/lib/libzstd.a"))
      libs = []
      libs.push("-L" + brew + "/lib")
      libs.push("-lzstd")
    elsif cflags.size > 0
      libs = []
      libs.push("-lzstd")
  # Linux: zstd on default paths needs only -lzstd at link.
  if libs.size == 0 && IS_LINUX
    if regular_file?("/usr/include/zstd.h") || capture("ls /usr/lib/*/libzstd.so* 2>/dev/null").strip != ""
      libs = []
      libs.push("-lzstd")
  value = []
  value.push(cflags.join(" "))
  value.push(libs.join(" "))
  cached_probe_write("zstd", fp, value)
  value

-> probe_openssl_prefix
  markers = []
  brew = build_homebrew_prefix("")
  formula_prefix = build_homebrew_prefix("openssl@3")
  if brew != ""
    markers.push(brew + "/bin/brew")
  if formula_prefix != ""
    markers.push(formula_prefix)
  fp = marker_fingerprint(markers)
  cached = cached_probe_read("openssl_prefix", fp)
  if cached != nil && cached.size >= 1
    return cached[0]
  prefix = formula_prefix
  value = []
  value.push(prefix)
  cached_probe_write("openssl_prefix", fp, value)
  prefix

# ── Runtime archive ─────────────────────────────────────────────

<< ""
<< BOLD + "==> Runtime: compiling C sources" + RESET
t_runtime_start = clock_ms()

tls_enabled = env("TLS") != nil || env("TUNGSTEN_TLS") != nil
http2_enabled = env("HTTP2") != nil || env("TUNGSTEN_HTTP2") != nil

runtime_srcs = []
runtime_srcs.push("runtime.c")
runtime_srcs.push("terminal_input.c")
runtime_srcs.push("ssmr_witness.c")
runtime_srcs.push("lexchar_tables.c")
runtime_srcs.push("tls_stub.c")
runtime_srcs.push("aks.c")
if IS_DARWIN
  runtime_srcs.push("event_kqueue.c")
elsif IS_LINUX
  runtime_srcs.push(env("USE_IOURING") != nil ? "event_iouring.c" : "event_epoll.c")
if tls_enabled
  runtime_srcs.push("tls.c")
if IS_DARWIN
  runtime_srcs.push("metal.m")
  runtime_srcs.push("blas_bridge.c")
  runtime_srcs.push("hid_bridge.m")

openssl_prefix = probe_openssl_prefix()
tls_flags = []
if tls_enabled && regular_file?(openssl_prefix + "/include/openssl/ssl.h")
  tls_flags.push("-DTUNGSTEN_TLS")
  tls_flags.push("-I" + openssl_prefix + "/include")

nghttp2_prefix = build_homebrew_prefix("libnghttp2")
http2_flags = []
http2_libs = []
if http2_enabled && regular_file?(nghttp2_prefix + "/include/nghttp2/nghttp2.h")
  http2_flags.push("-DTUNGSTEN_HTTP2")
  http2_flags.push("-I" + nghttp2_prefix + "/include")
  http2_libs.push("-L" + nghttp2_prefix + "/lib")
  http2_libs.push("-lnghttp2")
if http2_flags.size > 0
  runtime_srcs.push("http2.c")

onig_value = probe_onig()
onig_cflags = split_ws(onig_value[0])
onig_libs = split_ws(onig_value[1])

zstd_value = probe_zstd()
zstd_cflags = split_ws(zstd_value[0])
zstd_libs = split_ws(zstd_value[1])

# Optional-zstd contract: hosts without libzstd (or with the disable env)
# link the stub — same symbols, aborts only if a zstd slab path runs.
zstd_available = zstd_libs.size > 0 && env_or_empty("TUNGSTEN_BOOTSTRAP_DISABLE_ZSTD") != "1"
if !zstd_available
  zstd_cflags = []
  zstd_libs = []
runtime_srcs.push(zstd_available ? "slab_zstd.c" : "slab_zstd_stub.c")

runtime_cc = env_or_empty("TUNGSTEN_CC")
if runtime_cc == ""
  runtime_cc = "clang"
runtime_ar = env_or_empty("TUNGSTEN_AR")
if runtime_ar == ""
  sib = sibling_tool(runtime_cc, "llvm-ar")
  runtime_ar = sib == nil ? "ar" : sib
runtime_ranlib = env_or_empty("TUNGSTEN_RANLIB")
if runtime_ranlib == ""
  sib = sibling_tool(runtime_cc, "llvm-ranlib")
  runtime_ranlib = sib == nil ? "" : sib

toolchain_keys = []
toolchain_vals = []
toolchain_keys.push("TUNGSTEN_CC")
toolchain_vals.push(runtime_cc)
toolchain_keys.push("TUNGSTEN_AR")
toolchain_vals.push(runtime_ar)
if runtime_ranlib != ""
  toolchain_keys.push("TUNGSTEN_RANLIB")
  toolchain_vals.push(runtime_ranlib)

runtime_cache_schema = "runtime-cache-v2"
fast_clang_flags = []
if fast_mode
  fast_clang_flags.push("-ffast-math")
profile_cflags = []
profile_cflags.push(release_mode ? "-O3" : "-O1")
profile_cflags.push(debug_enabled ? "-g" : "-DNDEBUG")
cc_flags = profile_cflags + []
cc_flags.push("-pthread")
cc_flags = cc_flags + march_flags + fast_clang_flags
cc_flags.push("-c")
cc_flags = cc_flags + tls_flags + http2_flags + onig_cflags + zstd_cflags
runtime_objc_flags = profile_cflags + march_flags + fast_clang_flags
runtime_objc_flags.push("-c")
runtime_objc_flags.push("-x")
runtime_objc_flags.push("objective-c")
sanitize_flags = split_ws(env_or_empty("TUNGSTEN_SANITIZE"))
cc_flags = cc_flags + sanitize_flags
runtime_objc_flags = runtime_objc_flags + sanitize_flags
if IS_LINUX
  cc_flags.push("-D_DEFAULT_SOURCE")

# w_lexchar_cache.c is #included by runtime.c — must be in the hash inputs.
runtime_dependency_files = []
i = 0
while i < runtime_srcs.size
  runtime_dependency_files.push(RUNTIME_DIR + "/" + runtime_srcs[i])
  i = i + 1
runtime_headers = capture("ls " + shq(RUNTIME_DIR) + "/*.h 2>/dev/null").split("\n")
i = 0
while i < runtime_headers.size
  if runtime_headers[i].strip != ""
    runtime_dependency_files.push(runtime_headers[i].strip)
  i = i + 1
runtime_dependency_files.push(RUNTIME_DIR + "/w_lexchar_cache.c")
runtime_dependency_files.push(RUNTIME_DIR + "/w_char_table.c")
runtime_dependency_files.push(RUNTIME_DIR + "/generated/bigint_thresholds.h")
runtime_dependency_files = uniq_strings(runtime_dependency_files)
runtime_dependency_files = capture("printf '%s\\n' " + flags_to_cmd(runtime_dependency_files) + " | LC_ALL=C sort").split("\n")
filtered_deps = []
i = 0
while i < runtime_dependency_files.size
  if runtime_dependency_files[i].strip != ""
    filtered_deps.push(runtime_dependency_files[i].strip)
  i = i + 1
runtime_dependency_files = filtered_deps

-> digest_file_list(paths)
  buf = StringBuffer(paths.size * 48)
  i = 0
  while i < paths.size
    buf << project_relative_path(paths[i])
    buf << "\t"
    buf << file_sha(paths[i])
    buf << "\n"
    i = i + 1
  Digest.sha256(buf.to_s)

runtime_deps_digest = digest_file_list(runtime_dependency_files)
runtime_compile_key = Digest.sha256(runtime_cache_schema + "\n" + runtime_deps_digest + "\n" + join_tab(cc_flags) + "\n" + join_tab(runtime_objc_flags) + "\n" + PLATFORM + "\n" + tool_identity(runtime_cc) + "\n" + tool_identity(runtime_ar) + "\n" + AMBIENT_TOOLCHAIN)
runtime_archive = BUILD_CACHE_DIR + "/runtime-" + runtime_compile_key + ".a"
runtime_handoff_ready = handoff_runtime != "" && regular_file?(handoff_runtime)
if runtime_handoff_ready
  runtime_archive = handoff_runtime

runtime_env_contents = "runtime-env-v1\n" + zstd_cflags.join(" ") + "\n" + zstd_libs.join(" ") + "\n" + onig_cflags.join(" ") + "\n" + onig_libs.join(" ") + "\n" + (IS_DARWIN ? "Darwin" : (IS_LINUX ? "Linux" : "")) + "\n" + runtime_cc + "\n" + runtime_ar + "\n" + runtime_ranlib + "\n"
runtime_env_manifest = BUILD_CACHE_DIR + "/runtime-env-" + Digest.sha256(runtime_env_contents) + ".env"
runtime_current_manifest = BUILD_CACHE_DIR + "/runtime-current.manifest"

if force_build
  << DIM + "--force: rebuilding all requested phases" + RESET

if runtime_handoff_ready
  << "    " + GREEN + "REUSED" + RESET + " bootstrap runtime " + DIM + aligned_ms(clock_ms() - t_runtime_start) + RESET
elsif !force_build && regular_file?(runtime_archive)
  << "    " + GREEN + "CACHED" + RESET + " runtime " + DIM + aligned_ms(clock_ms() - t_runtime_start) + RESET
else
  runtime_tmp_dir = ccall("__w_mkdtemp", "tungsten-runtime")
  if runtime_tmp_dir == nil
    die(RED + "Failed to create runtime temp dir" + RESET)
  compile_procs = []
  compile_objs = []
  i = 0
  while i < runtime_srcs.size
    src = runtime_srcs[i]
    src_path = RUNTIME_DIR + "/" + src
    obj_base = src.replace(".c", "").replace(".m", "")
    obj_path = runtime_tmp_dir + "/" + obj_base + ".o"
    flags = src.ends_with?(".m") ? runtime_objc_flags : cc_flags
    cmd = shq(runtime_cc) + flags_to_cmd(flags) + " " + shq(src_path) + " -o " + shq(obj_path)
    sa = []
    sa.push("/bin/sh")
    sa.push("-c")
    sa.push(cmd)
    compile_procs.push(Process.spawn(sa))
    compile_objs.push(obj_path)
    i = i + 1
  failed_src = ""
  i = 0
  while i < compile_procs.size
    if compile_procs[i].wait != 0 && failed_src == ""
      failed_src = runtime_srcs[i]
    i = i + 1
  if failed_src != ""
    eputs(RED + "Failed to compile " + failed_src + RESET)
    exit(1)
  tmp_archive = runtime_tmp_dir + "/" + basename_of(runtime_archive)
  if !sh_ok(shq(runtime_ar) + " rcs " + shq(tmp_archive) + flags_to_cmd(compile_objs))
    eputs(RED + "Failed to archive runtime" + RESET)
    exit(1)
  atomic_copy(tmp_archive, runtime_archive)
  sh_ok("rm -rf " + shq(runtime_tmp_dir))
  << "    " + GREEN + "built" + RESET + "  runtime " + DIM + aligned_ms(clock_ms() - t_runtime_start) + RESET

atomic_write(runtime_env_contents, runtime_env_manifest)
atomic_write(basename_of(runtime_archive) + "\n" + basename_of(runtime_env_manifest) + "\n", runtime_current_manifest)

t_runtime_end = clock_ms()

# compiler_probe_env — the compiler skips its own pkg-config probes.
probe_keys = []
probe_vals = []
probe_keys.push("TUNGSTEN_ZSTD_CFLAGS")
probe_vals.push(zstd_cflags.join(" "))
probe_keys.push("TUNGSTEN_ZSTD_LDFLAGS")
probe_vals.push(zstd_libs.join(" "))
probe_keys.push("TUNGSTEN_ONIG_CFLAGS")
probe_vals.push(onig_cflags.join(" "))
probe_keys.push("TUNGSTEN_ONIG_LDFLAGS")
probe_vals.push(onig_libs.join(" "))
probe_keys.push("TUNGSTEN_HTTP2_LDFLAGS")
probe_vals.push(http2_libs.join(" "))
probe_keys.push("TUNGSTEN_OS")
probe_vals.push(IS_DARWIN ? "Darwin" : (IS_LINUX ? "Linux" : ""))
i = 0
while i < toolchain_keys.size
  probe_keys.push(toolchain_keys[i])
  probe_vals.push(toolchain_vals[i])
  i = i + 1

bootstrap_compiler_clang_opt = env_or_empty("TUNGSTEN_CLANG_OPT")
if bootstrap_compiler_clang_opt == ""
  opt_level = release_mode ? "-O3" : "-O1"
  debug_part = debug_enabled ? " -g" : ""
  fast_part = fast_mode ? " -ffast-math" : ""
  bootstrap_compiler_clang_opt = opt_level + debug_part + fast_part

# ── tree_sha / bit helpers ──────────────────────────────────────

# SHA over source files under the given roots (dirs pruned: .git .bundle
# .cache node_modules tmp; extensions: .rb .w .c .h .gemspec .lock),
# 16 hex chars. find|sort gives a deterministic walk.
-> tree_sha_files(path)
  full = path.starts_with?("/") ? path : ROOT + "/" + path
  if file_directory?(full)
    finder = "find " + shq(full) + " \\( -name .git -o -name .bundle -o -name .cache -o -name node_modules -o -name tmp \\) -prune -o -type f \\( -name '*.rb' -o -name '*.w' -o -name '*.c' -o -name '*.h' -o -name '*.gemspec' -o -name '*.lock' \\) -print 2>/dev/null | LC_ALL=C sort"
    listing = capture(finder).split("\n")
    out = []
    i = 0
    while i < listing.size
      if listing[i].strip != ""
        out.push(listing[i].strip)
      i = i + 1
    return out
  if regular_file?(full)
    single = []
    single.push(full)
    return single
  []

-> tree_sha(paths)
  buf = StringBuffer(4096)
  i = 0
  while i < paths.size
    files = tree_sha_files(paths[i])
    j = 0
    while j < files.size
      buf << project_relative_path(files[j])
      buf << "\t"
      buf << file_sha(files[j])
      buf << "\n"
      j = j + 1
    i = i + 1
  Digest.sha256(buf.to_s).slice(0, 16)

-> find_bit_root(dir)
  d = dir
  while d != "/" && d != ""
    if regular_file?(d + "/Bitfile")
      return d
    d = dirname_of(d)
  nil

# Extract quoted strings from Bitfile include/includes lines.
-> extract_quoted(text)
  out = []
  i = 0
  current = nil
  quote = ""
  while i < text.size
    c = text.slice(i, 1)
    if current == nil
      if c == "\"" || c == "'"
        current = ""
        quote = c
    elsif c == quote
      out.push(current)
      current = nil
    else
      current = current + c
    i = i + 1
  out

-> strip_bitfile_comment(line)
  i = 0
  while i < line.size
    c = line.slice(i, 1)
    if c == "#" && i > 0
      prev = line.slice(i - 1, 1)
      if prev == " " || prev == "\t"
        return line.slice(0, i)
    i = i + 1
  line

-> bitfile_includes(bit_root)
  bitfile = bit_root + "/Bitfile"
  text = read_file(bitfile)
  if text == nil
    return []
  includes = []
  lines = text.split("\n")
  in_includes_list = false
  i = 0
  while i < lines.size
    line = strip_bitfile_comment(lines[i])
    stripped = line.strip
    if in_includes_list
      q = extract_quoted(line)
      j = 0
      while j < q.size
        includes.push(q[j])
        j = j + 1
      if str_has?(line, "]")
        in_includes_list = false
    elsif stripped.starts_with?("include ") || stripped.starts_with?("include\t")
      q = extract_quoted(line)
      j = 0
      while j < q.size
        includes.push(q[j])
        j = j + 1
    elsif stripped.starts_with?("includes")
      q = extract_quoted(line)
      j = 0
      while j < q.size
        includes.push(q[j])
        j = j + 1
      if !str_has?(line, "]")
        in_includes_list = true
    i = i + 1
  out = []
  i = 0
  while i < includes.size
    p = includes[i]
    abs = p.starts_with?("/") ? p : bit_root + "/" + p
    out.push(File.expand_path(abs))
    i = i + 1
  uniq_strings(out)

CWD = capture("pwd -P").strip
bit_root_found = find_bit_root(CWD)
bit_only = bit_root_found != nil && bit_root_found != ROOT
skip_bits = skip_bits_requested || (!bit_only && (stage0_only || stage1_only || stage2_only))

# ── install_compiler (content-addressed signed cache) ───────────

-> codesign_ok(path)
  if !IS_DARWIN
    return true
  sh_ok("codesign --force -s - " + shq(path) + " >/dev/null 2>&1")

-> install_compiler(src, label, announce)
  sidemap = src + ".sidemap"
  sidemap_sha = regular_file?(sidemap) ? file_sha(sidemap) : "missing:sidemap"
  install_sha = Digest.sha256(file_sha(src) + ":" + sidemap_sha)
  install_cache_dir = BUILD_CACHE_DIR + "/compiler-installs"
  make_dirs(install_cache_dir)
  signed_cache = install_cache_dir + "/" + install_sha
  signed_sidemap_cache = signed_cache + ".sidemap"
  installed_sidemap = COMPILER_BIN + ".sidemap"
  if !(executable?(signed_cache) && optional_cache_complete?(signed_sidemap_cache))
    tmp_cache = signed_cache + "." + PID + ".tmp"
    sh_ok("cp " + shq(src) + " " + shq(tmp_cache) + " && chmod 755 " + shq(tmp_cache))
    if !codesign_ok(tmp_cache)
      eputs(RED + "codesign failed for " + COMPILER_BIN + RESET)
      sh_ok("rm -f " + shq(tmp_cache))
      exit(1)
    sh_ok("mv -f " + shq(tmp_cache) + " " + shq(signed_cache))
    publish_optional_file(sidemap, signed_sidemap_cache)
  sidemap_matches = false
  if regular_file?(signed_sidemap_cache)
    sidemap_matches = same_file_content?(signed_sidemap_cache, installed_sidemap)
  else
    sidemap_matches = !regular_file?(installed_sidemap)
  if executable?(COMPILER_BIN) && same_file_content?(signed_cache, COMPILER_BIN) && sidemap_matches
    return true
  atomic_copy(signed_cache, COMPILER_BIN)
  sh_ok("chmod 755 " + shq(COMPILER_BIN))
  restore_optional_file(signed_sidemap_cache, installed_sidemap)
  if announce
    suffix = label == "" ? "" : " " + DIM + "(" + label + ")" + RESET
    << "    " + GREEN + "installed" + RESET + " " + COMPILER_BIN + suffix
  true

# ── Stage 0: C VM build key + build ─────────────────────────────

-> c_vm_dependency_files
  files = []
  patterns = capture("ls " + shq(C_INTERP_DIR) + "/src/*.c " + shq(C_INTERP_DIR) + "/src/*.inc " + shq(C_INTERP_DIR) + "/include/*.h 2>/dev/null").split("\n")
  i = 0
  while i < patterns.size
    if patterns[i].strip != ""
      files.push(patterns[i].strip)
    i = i + 1
  files.push(C_INTERP_DIR + "/Makefile")
  files.push(RUNTIME_DIR + "/wvalue.h")
  files.push(RUNTIME_DIR + "/w_lexchar_cache.c")
  files = uniq_strings(files)
  sorted = capture("printf '%s\\n' " + flags_to_cmd(files) + " | LC_ALL=C sort").split("\n")
  out = []
  i = 0
  while i < sorted.size
    if sorted[i].strip != ""
      out.push(sorted[i].strip)
    i = i + 1
  out

-> make_assignments_key
  makeflags = env_or_empty("MAKEFLAGS")
  parts = split_ws(makeflags)
  keep = []
  i = 0
  while i < parts.size
    p = parts[i]
    if str_has?(p, "=") && !p.starts_with?("--jobserver")
      keep.push(p)
    i = i + 1
  if keep.size == 0
    return ""
  capture("printf '%s\\n' " + flags_to_cmd(keep) + " | LC_ALL=C sort").strip.gsub("\n", "\t")

-> c_vm_build_key
  dep_digest = digest_file_list(c_vm_dependency_files())
  cc = env_or_empty("CC")
  cc_for_identity = cc == "" ? "clang" : cc
  Digest.sha256(dep_digest + "\n" + PLATFORM + "\n" + tool_identity(cc_for_identity) + "\n" + env_or_empty("CC") + "\n" + env_or_empty("CFLAGS") + "\n" + env_or_empty("CPPFLAGS") + "\n" + env_or_empty("ARCH_FLAGS") + "\n" + env_or_empty("LDFLAGS") + "\n" + AMBIENT_TOOLCHAIN + "\n" + make_assignments_key())

-> c_vm_make_jobs
  makeflags = env_or_empty("MAKEFLAGS")
  parts = split_ws(makeflags)
  i = 0
  while i < parts.size
    if parts[i] == "-j" || parts[i].starts_with?("-j") || parts[i].starts_with?("--jobs")
      return ""
    i = i + 1
  requested = env_or_empty("TUNGSTEN_BUILD_JOBS")
  jobs = requested == "" ? System.cpu_count : requested.to_i
  if jobs < 1
    jobs = 1
  if jobs > 8
    jobs = 8
  " -j " + jobs.to_s

# Returns [verb, elapsed_ms, identity_binary, key]
-> ensure_c_interp(force_build)
  key = c_vm_build_key()
  cached_build_dir = "build/identity-" + key
  cached_binary = C_INTERP_DIR + "/" + cached_build_dir + "/tungsten-c"
  scratch_build_dir = cached_build_dir + "-build-" + PID
  verb = "cached"
  elapsed = 0
  if force_build || !executable?(cached_binary)
    t_start = clock_ms()
    log_path = "/tmp/tungsten-c-vm-build-" + PID + ".log"
    sh_ok("rm -rf " + shq(C_INTERP_DIR + "/" + scratch_build_dir))
    make_cmd = "make -B" + c_vm_make_jobs() + " -C " + shq(C_INTERP_DIR) + " BUILD_DIR=" + shq(scratch_build_dir) + " > " + shq(log_path) + " 2>&1"
    if !sh_ok(make_cmd)
      log = read_file(log_path)
      if log != nil
        eputs(log)
      sh_ok("rm -rf " + shq(C_INTERP_DIR + "/" + scratch_build_dir))
      eputs("Failed to build implementations/c (make -C " + C_INTERP_DIR + ")")
      exit(1)
    verb = "built"
    elapsed = clock_ms() - t_start
    make_dirs(dirname_of(cached_binary))
    atomic_copy(C_INTERP_DIR + "/" + scratch_build_dir + "/tungsten-c", cached_binary)
    sh_ok("chmod 755 " + shq(cached_binary))
    sh_ok("rm -rf " + shq(C_INTERP_DIR + "/" + scratch_build_dir))
  if !executable?(cached_binary)
    eputs("C VM build produced no executable at " + cached_binary)
    exit(1)
  if !same_file_content?(cached_binary, C_INTERP)
    atomic_copy(cached_binary, C_INTERP)
    sh_ok("chmod 755 " + shq(C_INTERP))
  r = []
  r.push(verb)
  r.push(elapsed.to_s)
  r.push(cached_binary)
  r.push(key)
  r

# ── PGO post-step ───────────────────────────────────────────────

-> run_pgo_post_step(stage2_bin, label, build_scratch_dir, probe_prefix)
  << ""
  << BOLD + "==> PGO: profile-guided optimization" + RESET
  t_pgo_start = clock_ms()
  pgo_dir = build_scratch_dir + "/pgo"
  pgo_profraw = pgo_dir + "/default-%p.profraw"
  pgo_profdata = pgo_dir + "/default.profdata"
  pgo_instrumented = pgo_dir + "/tungsten-instrumented"
  pgo_optimized = pgo_dir + "/tungsten-pgo"
  make_dirs(pgo_dir)
  pgo_fast_flag = FAST_MODE ? " -ffast-math" : ""
  << "    " + DIM + "instrumenting..." + RESET
  instr_env = "TUNGSTEN_CLANG_OPT=" + shq("-O3 -fprofile-generate=" + pgo_dir + " -mllvm -vp-counters-per-site=8" + pgo_fast_flag) + " TUNGSTEN_INCREMENTAL=0 "
  if sh("cd " + shq(ROOT) + " && " + instr_env + shq(stage2_bin) + " compile " + shq(TUNGSTEN_W) + " --out " + shq(pgo_instrumented) + STAGE_FLAGS_CMD) != 0
    eputs(RED + "PGO instrumentation build failed" + RESET)
    exit(1)
  sh_ok("rm -f " + shq(pgo_dir) + "/*.profraw")
  << "    " + DIM + "profiling..." + RESET
  profile_env = "LLVM_PROFILE_FILE=" + shq(pgo_profraw) + " TUNGSTEN_INCREMENTAL=0 "
  if sh("cd " + shq(ROOT) + " && " + profile_env + shq(pgo_instrumented) + " compile " + shq(TUNGSTEN_W) + " --out " + shq(pgo_dir + "/train-out") + STAGE_FLAGS_CMD) != 0
    eputs(RED + "PGO profiling run failed" + RESET)
    exit(1)
  llvm_profdata = capture("xcrun -f llvm-profdata 2>/dev/null").strip
  if llvm_profdata == ""
    llvm_profdata = "llvm-profdata"
  raws = capture("ls " + shq(pgo_dir) + "/*.profraw 2>/dev/null").split("\n")
  raw_count = 0
  raw_cmd = ""
  i = 0
  while i < raws.size
    if raws[i].strip != ""
      raw_count = raw_count + 1
      raw_cmd = raw_cmd + " " + shq(raws[i].strip)
    i = i + 1
  if raw_count == 0 || !sh_ok(shq(llvm_profdata) + " merge -sparse" + raw_cmd + " -o " + shq(pgo_profdata))
    eputs(RED + "llvm-profdata merge failed" + RESET)
    exit(1)
  << "    " + DIM + "optimizing..." + RESET
  opt_env = "TUNGSTEN_CLANG_OPT=" + shq("-O3 -fprofile-use=" + pgo_profdata + " -Wno-profile-instr-unprofiled -Wno-profile-instr-out-of-date" + pgo_fast_flag) + " TUNGSTEN_INCREMENTAL=0 "
  if sh("cd " + shq(ROOT) + " && " + opt_env + shq(stage2_bin) + " compile " + shq(TUNGSTEN_W) + " --out " + shq(pgo_optimized) + STAGE_FLAGS_CMD) != 0
    eputs(RED + "PGO optimization build failed" + RESET)
    exit(1)
  << "    " + DIM + "PGO: " + ms(clock_ms() - t_pgo_start) + RESET
  << ""
  install_compiler(pgo_optimized, label, true)

FAST_MODE = fast_mode

# ── Bootstrap compiler ──────────────────────────────────────────

t0 = clock_ms()
t1 = t0
t2 = t0

probe_env_prefix = env_prefix(probe_keys, probe_vals)
probe_env_kv = env_kv_join(probe_keys, probe_vals)
toolchain_env_prefix = env_prefix(toolchain_keys, toolchain_vals)

compiler_source_paths = []
compiler_source_paths.push(compiler_dir_name + "/tungsten.w")
compiler_source_paths.push(compiler_dir_name + "/lib")
compiler_source_paths.push("core")
compiler_source_paths.push("languages/tungsten/lexers")

if !bit_only
  stage1 = build_scratch_dir + "/tungsten.wc"
  stage2 = build_scratch_dir + "/tungsten-self-hosted.wc"
  stage_ll_dir = build_scratch_dir + "/ll"
  bootstrap_ll_tag = "c"
  if use_spinel_bootstrap
    bootstrap_ll_tag = "spinel"
  elsif !use_c_bootstrap
    bootstrap_ll_tag = pgo_build ? "pgo-ruby" : "ruby"
  stage1_ll = stage_ll_dir + "/stage1-" + bootstrap_ll_tag + ".ll"
  stage2_ll = stage_ll_dir + "/stage2-" + bootstrap_ll_tag + ".ll"
  make_dirs(stage_ll_dir)

  lex_table_path = env_or_empty("TUNGSTEN_LEX64_TABLE")
  if lex_table_path == ""
    lex_table_path = ROOT + "/languages/tungsten/tungsten.lex64"

  if use_c_bootstrap
    c_stage_cache_schema = "c-stage-content-v3"
    c_stage1_sources_sha = tree_sha(compiler_source_paths)
    << ""
    << BOLD + "==> Stage 0: implementations/c VM" + RESET
    if handoff_stage0 != "" && executable?(handoff_stage0)
      vm_verb = "reused"
      vm_elapsed = 0
      c_interp_for_build = handoff_stage0
      c_vm_key_for_build = "bootstrap-" + file_sha(handoff_stage0)
    else
      vm = ensure_c_interp(force_build)
      vm_verb = vm[0]
      vm_elapsed = vm[1].to_i
      c_interp_for_build = vm[2]
      c_vm_key_for_build = vm[3]
    verb_str = vm_verb == "cached" ? GREEN + "CACHED" + RESET : (vm_verb == "reused" ? GREEN + "REUSED" + RESET : GREEN + "built " + RESET)
    << "    " + verb_str + " stage0 " + DIM + aligned_ms(vm_elapsed) + RESET

    requested_manifest = env_or_empty("TUNGSTEN_BUILD_MANIFEST")
    if requested_manifest != ""
      if !requested_manifest.starts_with?("/")
        requested_manifest = ROOT + "/" + requested_manifest
      make_dirs(dirname_of(requested_manifest))
      atomic_write("tungsten-build-manifest-v1\n" + c_interp_for_build + "\n" + runtime_archive + "\n" + runtime_env_manifest + "\n", requested_manifest)

    << ""
    << BOLD + "==> Stage 1: implementations/c VM compiles tungsten.w" + RESET
    stage1_started = clock_ms()
    # Fixed-point builds always use the canonical parser (fast parse
    # intentionally emits different stage-1 IR).
    s1_keys = probe_keys + []
    s1_vals = probe_vals + []
    s1_keys.push("TUNGSTEN_C_FAST_PARSE")
    s1_vals.push("0")
    s1_keys.push("TUNGSTEN_CLANG_OPT")
    s1_vals.push("-O0")
    s1_keys.push("TUNGSTEN_LEX64_TABLE")
    s1_vals.push(lex_table_path)
    c_stage1_identity = Digest.sha256(c_stage1_sources_sha + "\n" + c_stage_cache_schema + "\n" + runtime_compile_key + "\n" + c_vm_key_for_build + "\n" + file_sha(c_interp_for_build) + "\n" + file_sha(lex_table_path) + "\n" + compiler_dir_name + "\n" + join_tab(stage_flags) + "\n" + env_or_empty("TUNGSTEN_MARCH_ARGS") + "\n" + AMBIENT_TOOLCHAIN + "\n" + env_kv_join(s1_keys, s1_vals))
    c_stage1_cached = BUILD_CACHE_DIR + "/c-vm-stage1-" + c_stage1_identity
    c_stage1_cached_ll = c_stage1_cached + ".ll"
    c_stage1_cached_sidemap = c_stage1_cached + ".sidemap"
    stage1_handoff_ready = handoff_stage1 != "" && executable?(handoff_stage1) && handoff_stage1_ll != "" && regular_file?(handoff_stage1_ll)
    if stage1_handoff_ready
      atomic_copy(handoff_stage1, stage1)
      atomic_copy(handoff_stage1_ll, stage1_ll)
      if handoff_stage1_sidemap != "" && regular_file?(handoff_stage1_sidemap)
        atomic_copy(handoff_stage1_sidemap, stage1 + ".sidemap")
      else
        sh_ok("rm -f " + shq(stage1 + ".sidemap"))
      t1 = clock_ms()
      << "    " + GREEN + "REUSED" + RESET + " bootstrap stage1 " + DIM + aligned_ms(t1 - stage1_started) + RESET
    elsif !force_build && executable?(c_stage1_cached) && regular_file?(c_stage1_cached_ll) && optional_cache_complete?(c_stage1_cached_sidemap)
      sh_ok("cp " + shq(c_stage1_cached) + " " + shq(stage1))
      sh_ok("cp " + shq(c_stage1_cached_ll) + " " + shq(stage1_ll))
      restore_optional_file(c_stage1_cached_sidemap, stage1 + ".sidemap")
      t1 = clock_ms()
      << "    " + GREEN + "CACHED" + RESET + " stage1 " + DIM + aligned_ms(t1 - stage1_started) + " (" + c_stage1_identity.slice(0, 16) + ")" + RESET
    else
      sh_ok("rm -f " + shq(stage1_ll))
      # -O0 stage-1 link: the binary is throwaway (only produces stage 2).
      s1_env = env_prefix(s1_keys, s1_vals) + "TUNGSTEN_LL_DIR=" + shq(stage_ll_dir) + " TUNGSTEN_LL_PATH=" + shq(stage1_ll) + " "
      stage1_log = "/tmp/tungsten-c-stage1.log"
      stage1_link = release_mode ? "" : " --runtime " + shq(runtime_archive) + " --no-lto"
      s1_cmd = "cd " + shq(ROOT) + " && " + s1_env + shq(c_interp_for_build) + " " + shq(TUNGSTEN_W) + " compile " + shq(TUNGSTEN_W) + " --out " + shq(stage1) + STAGE_FLAGS_CMD + stage1_link + " > " + shq(stage1_log) + " 2>&1"
      if !sh_ok(s1_cmd)
        log = read_file(stage1_log)
        if log != nil
          eputs(log)
        eputs(RED + "Stage 1 (C VM) failed" + RESET)
        exit(1)
      if !codesign_ok(stage1)
        eputs(RED + "codesign failed for C VM stage 1" + RESET)
        exit(1)
      atomic_copy(stage1, c_stage1_cached)
      if regular_file?(stage1_ll)
        atomic_copy(stage1_ll, c_stage1_cached_ll)
      publish_optional_file(stage1 + ".sidemap", c_stage1_cached_sidemap)
      t1 = clock_ms()
      << "    " + GREEN + "built " + RESET + " stage1 " + DIM + aligned_ms(t1 - stage1_started) + RESET

    if stage1_only
      install_compiler(stage1, "C VM stage 1 only", true)
      t2 = t1
    else
      << ""
      << BOLD + "==> Stage 2: Stage-1 binary compiles tungsten.w" + RESET
      stage2_started = clock_ms()
      s2_keys = probe_keys + []
      s2_vals = probe_vals + []
      s2_keys.push("TUNGSTEN_CLANG_OPT")
      s2_vals.push(bootstrap_compiler_clang_opt)
      s2_keys.push("TUNGSTEN_LEX64_TABLE")
      s2_vals.push(lex_table_path)
      c_stage2_identity = Digest.sha256(c_stage1_identity + "\n" + file_sha(stage1) + "\n" + c_stage1_sources_sha + "\n" + c_stage_cache_schema + "\n" + runtime_compile_key + "\n" + join_tab(stage_flags) + "\n" + env_or_empty("TUNGSTEN_MARCH_ARGS") + "\n" + AMBIENT_TOOLCHAIN + "\n" + env_kv_join(s2_keys, s2_vals))
      c_stage2_cached = BUILD_CACHE_DIR + "/c-vm-stage2-" + c_stage2_identity
      c_stage2_cached_ll = c_stage2_cached + ".ll"
      c_stage2_cached_sidemap = c_stage2_cached + ".sidemap"
      if !force_build && executable?(c_stage2_cached) && regular_file?(c_stage2_cached_ll) && optional_cache_complete?(c_stage2_cached_sidemap)
        sh_ok("cp " + shq(c_stage2_cached) + " " + shq(stage2))
        sh_ok("cp " + shq(c_stage2_cached_ll) + " " + shq(stage2_ll))
        restore_optional_file(c_stage2_cached_sidemap, stage2 + ".sidemap")
        t2 = clock_ms()
        << "    " + GREEN + "CACHED" + RESET + " stage2 " + DIM + aligned_ms(t2 - stage2_started) + " (" + c_stage2_identity.slice(0, 16) + ")" + RESET
      else
        sh_ok("rm -f " + shq(stage2_ll))
        s2_env = env_prefix(s2_keys, s2_vals) + "TUNGSTEN_LL_DIR=" + shq(stage_ll_dir) + " TUNGSTEN_LL_PATH=" + shq(stage2_ll) + " "
        stage2_log = "/tmp/tungsten-c-stage2.log"
        stage2_link = release_mode ? "" : " --runtime " + shq(runtime_archive) + " --no-lto"
        s2_cmd = "cd " + shq(ROOT) + " && " + s2_env + shq(stage1) + " compile " + shq(TUNGSTEN_W) + " --out " + shq(stage2) + STAGE_FLAGS_CMD + stage2_link + " > " + shq(stage2_log) + " 2>&1"
        s2_status = sh(s2_cmd)
        if s2_status != 0
          log = read_file(stage2_log)
          if log != nil
            eputs(log)
          eputs(RED + "Stage 2 failed" + RESET + " (exit " + s2_status.to_s + ")")
          exit(1)
        t2 = clock_ms()
        if !regular_file?(stage2)
          eputs(RED + "Stage 2 produced no output" + RESET + " " + DIM + "(" + stage2 + ")" + RESET)
          eputs("    " + DIM + "stage 1 binary at " + stage1 + " ran cleanly but didn't write the output file —" + RESET)
          eputs("    " + DIM + "likely emit_ir or link_binary in compiler/tungsten.w bottomed out under the" + RESET)
          eputs("    " + DIM + "C VM. Check " + stage2_log + " for clang/runtime errors." + RESET)
          exit(1)
        atomic_copy(stage2, c_stage2_cached)
        if regular_file?(stage2_ll)
          atomic_copy(stage2_ll, c_stage2_cached_ll)
        publish_optional_file(stage2 + ".sidemap", c_stage2_cached_sidemap)
        << "    " + GREEN + "built " + RESET + " stage2 " + DIM + aligned_ms(t2 - stage2_started) + RESET

      << ""
      verify_started = clock_ms()
      verified = same_file_content?(stage1_ll, stage2_ll)
      verify_elapsed = clock_ms() - verify_started
      if verified
        << "    " + GREEN + "VERIFIED" + RESET + " " + DIM + "stage 1 .ll == stage 2 .ll (" + ms(verify_elapsed) + ")" + RESET
      else
        # Warn and ship stage 2 anyway (a false negative must not leave
        # the user with no installed compiler).
        eputs("    " + RED + "WARNING" + RESET + " stage 1 and stage 2 .ll differ!")
        if regular_file?(stage1_ll) && regular_file?(stage2_ll)
          eputs("    " + DIM + "stage 1 .ll: " + file_sha(stage1_ll) + RESET)
          eputs("    " + DIM + "stage 2 .ll: " + file_sha(stage2_ll) + RESET)
        else
          eputs("    " + DIM + "missing emitted .ll for one or both stages" + RESET)

      << ""
      if pgo_build
        run_pgo_post_step(stage2, "C VM + PGO", build_scratch_dir, probe_env_prefix)
      else
        install_compiler(stage2, "C VM", true)
  elsif use_spinel_bootstrap
    stage1 = build_scratch_dir + "/tungsten-stage1"
    stage2 = build_scratch_dir + "/tungsten-stage2"
    spinel_dir = ROOT + "/implementations/spinel"
    spinel_build_dir = spinel_dir + "/build"
    spinel_bootstrap = spinel_dir + "/bin/bootstrap"
    spinel_build_stage0 = spinel_dir + "/bin/build_stage0"
    spinel_runtime = spinel_build_dir + "/runtime-stage0.a"
    spinel_stage0_log = spinel_build_dir + "/build_stage0.log"
    spinel_stage0_status = spinel_build_dir + "/tungsten-stage0.status"
    spinel_stage1_ll = spinel_build_dir + "/stage1-spinel.ll"
    spinel_stage2_ll = spinel_build_dir + "/stage2-spinel.ll"
    spinel_stage2_ll_dir = spinel_build_dir + "/stage2-ll"
    spinel_stage2_status = spinel_build_dir + "/tungsten-stage2.status"
    spinel_env = ""
    if env_or_empty("TUNGSTEN_CLANG_OPT") == ""
      spinel_env = spinel_env + "TUNGSTEN_CLANG_OPT=-O1 "
    sp_gc = env_or_empty("SP_GC_DISABLE")
    spinel_env = spinel_env + "SP_GC_DISABLE=" + shq(sp_gc == "" ? "1" : sp_gc) + " "
    if force_build
      spinel_env = spinel_env + "TUNGSTEN_SPINEL_FORCE_STAGE0=1 "
    if fast_mode
      spinel_env = spinel_env + "TUNGSTEN_SPINEL_FAST=1 "

    if stage0_only
      << ""
      << BOLD + "==> Compiler: Spinel stage 0" + RESET
      stage0_started = clock_ms()
      if !sh_ok(spinel_env + shq(spinel_build_stage0) + " > " + shq(spinel_stage0_log) + " 2>&1")
        log = read_file(spinel_stage0_log)
        if log != nil
          eputs(log)
        eputs(RED + "Spinel stage0 preparation failed" + RESET)
        exit(1)
      t1 = clock_ms()
      t2 = t1
      stage0_status = "built"
      st = read_file(spinel_stage0_status)
      if st != nil
        stage0_status = st.strip
      if stage0_status == "cached"
        << "    " + GREEN + "CACHED" + RESET + " stage0 " + DIM + aligned_ms(t1 - stage0_started) + RESET
      else
        << "    " + GREEN + "built" + RESET + "  stage0 " + DIM + aligned_ms(t1 - stage0_started) + RESET
    elsif stage2_only
      << ""
      << BOLD + "==> Stage 2: Spinel stage-1 binary compiles tungsten.w" + RESET
      if !executable?(stage1)
        eputs(RED + "No Spinel stage-1 binary at " + stage1 + " — run full build first" + RESET)
        exit(1)
      if !sh_ok(spinel_env + shq(spinel_build_stage0) + " > /dev/null")
        eputs(RED + "Spinel stage0 preparation failed" + RESET)
        exit(1)
      make_dirs(spinel_stage2_ll_dir)
      tmp_ll = spinel_stage2_ll_dir + "/tungsten.ll"
      sh_ok("rm -f " + shq(tmp_ll))
      spinel_link = release_mode ? "" : " --runtime " + shq(spinel_runtime) + " --no-lto"
      s2_cmd = spinel_env + "TUNGSTEN_LL_DIR=" + shq(spinel_stage2_ll_dir) + " TUNGSTEN_LL_PATH=" + shq(tmp_ll) + " " + shq(stage1) + " compile compiler/tungsten.w" + spinel_link + STAGE_FLAGS_CMD + " --out " + shq(stage2)
      s2_status = sh(s2_cmd)
      if s2_status != 0
        eputs(RED + "Stage 2 failed" + RESET + " (exit " + s2_status.to_s + ")")
        exit(1)
      if regular_file?(tmp_ll)
        sh_ok("cp " + shq(tmp_ll) + " " + shq(spinel_stage2_ll))
      write_file(spinel_stage2_status, "built\n")
    else
      << ""
      label = stage1_only ? "Spinel bootstrap (stage 1 only)" : "Spinel bootstrap"
      << BOLD + "==> Compiler: " + label + RESET
      sp_env = spinel_env + "TUNGSTEN_SPINEL_STAGE2=" + shq(stage2) + " "
      if force_build
        sp_env = sp_env + "TUNGSTEN_SPINEL_FORCE_STAGE2=1 "
      if stage1_only
        sp_env = sp_env + "TUNGSTEN_SPINEL_STAGE1_ONLY=1 "
      if sh(sp_env + shq(spinel_bootstrap)) != 0
        eputs(RED + "Spinel bootstrap failed" + RESET)
        exit(1)

    if !stage0_only
      if regular_file?(spinel_stage1_ll)
        sh_ok("cp " + shq(spinel_stage1_ll) + " " + shq(stage1_ll))
      if regular_file?(spinel_stage2_ll)
        sh_ok("cp " + shq(spinel_stage2_ll) + " " + shq(stage2_ll))
      t1 = clock_ms()
      t2 = t1
      if stage1_only
        install_compiler(stage1, "Spinel stage 1 only", true)
      else
        << ""
        << BOLD + "==> Verify: stage 1 .ll == stage 2 .ll" + RESET
        verify_started = clock_ms()
        verified = same_file_content?(stage1_ll, stage2_ll)
        verify_elapsed = clock_ms() - verify_started
        if verified
          << "    " + GREEN + "VERIFIED" + RESET + " " + DIM + "stage 1 .ll == stage 2 .ll (" + ms(verify_elapsed) + ")" + RESET
        else
          eputs("    " + RED + "ERROR" + RESET + " stage 1 and stage 2 .ll differ!")
          if regular_file?(stage1_ll) && regular_file?(stage2_ll)
            eputs("    " + DIM + "stage 1 .ll: " + file_sha(stage1_ll) + RESET)
            eputs("    " + DIM + "stage 2 .ll: " + file_sha(stage2_ll) + RESET)
          else
            eputs("    " + DIM + "missing emitted .ll for one or both stages" + RESET)
          exit(1)
        t2 = clock_ms()
        stage2_status = "built"
        st = read_file(spinel_stage2_status)
        if st != nil
          stage2_status = st.strip
        if stage2_status == "built"
          << ""
        install_compiler(stage2, stage2_only ? "Spinel stage 2" : "Spinel", stage2_status == "built")
  else
    # ── Ruby bootstrap path (developer option --ruby) ───────────
    legacy_lex_table = lex_table_path
    stage1_input_paths = []
    stage1_input_paths.push("implementations/ruby")
    i = 0
    while i < compiler_source_paths.size
      stage1_input_paths.push(compiler_source_paths[i])
      i = i + 1
    stage1_input_paths.push("runtime")
    stage1_input_paths.push("bin/tungsten")
    stage1_input_paths.push("bin/commands/build.w")
    stage1_input_sha = tree_sha(stage1_input_paths)
    stage1_sha = Digest.sha256(stage1_input_sha + ":" + runtime_compile_key + ":" + file_sha(legacy_lex_table)).slice(0, 16)
    stage1_cached = BUILD_CACHE_DIR + "/stage1-" + stage1_sha

    if !stage2_only
      if !force_build && executable?(stage1_cached)
        sh_ok("cp " + shq(stage1_cached) + " " + shq(stage1))
        << ""
        << BOLD + "==> Stage 1: cached" + RESET + " " + DIM + "(" + stage1_sha + ")" + RESET
        t1 = clock_ms()
      else
        ruby_label = executable?(CUSTOM_RUBY) ? "custom Ruby" : "system Ruby"
        s1_env = toolchain_env_prefix + "TUNGSTEN_LL_DIR=" + shq(stage_ll_dir) + " TUNGSTEN_LL_PATH=" + shq(stage1_ll) + " "
        if executable?(CUSTOM_RUBY)
          custom_gem_dir = ROOT + "/build/ruby/lib/ruby/gems/4.0.0"
          s1_env = s1_env + "GEM_HOME=" + shq(custom_gem_dir) + " GEM_PATH=" + shq(custom_gem_dir) + " "
          s1_cmd = s1_env + shq(CUSTOM_RUBY) + " " + shq(GEM_EXE) + " " + shq(TUNGSTEN_W) + " -- compile -v " + shq(TUNGSTEN_W) + " --out " + shq(stage1) + STAGE_FLAGS_CMD
        else
          s1_cmd = s1_env + shq(GEM_EXE) + " " + shq(TUNGSTEN_W) + " -- compile -v " + shq(TUNGSTEN_W) + " --out " + shq(stage1) + STAGE_FLAGS_CMD
        << ""
        << BOLD + "==> Stage 1: " + ruby_label + " compiles tungsten.w" + RESET
        sh_ok("rm -f " + shq(stage1_ll))
        if sh(s1_cmd) != 0
          eputs(RED + "Stage 1 failed" + RESET)
          exit(1)
        if !codesign_ok(stage1)
          eputs(RED + "codesign failed for stage 1" + RESET)
          exit(1)
        atomic_copy(stage1, stage1_cached)
        t1 = clock_ms()
        << "    " + DIM + "Stage 1: " + aligned_ms(t1 - t0) + RESET
    else
      t1 = t0
      if !regular_file?(stage1)
        eputs(RED + "No stage-1 binary at " + stage1 + " — run full build first" + RESET)
        exit(1)
      << BOLD + "==> Skipping Stage 1" + RESET + " " + DIM + "(reusing " + stage1 + ")" + RESET

    if stage1_only
      install_compiler(stage1, "stage 1 only", true)
      t2 = t1
    else
      stage2_input_paths = []
      i = 0
      while i < compiler_source_paths.size
        stage2_input_paths.push(compiler_source_paths[i])
        i = i + 1
      stage2_input_paths.push("runtime")
      stage2_input_paths.push("bin/tungsten")
      stage2_input_paths.push("bin/commands/build.w")
      stage2_input_sha = tree_sha(stage2_input_paths)
      stage2_sha = Digest.sha256(stage1_sha + ":" + stage2_input_sha + ":" + bootstrap_compiler_clang_opt).slice(0, 16)
      stage2_cached = BUILD_CACHE_DIR + "/stage2-" + stage2_sha

      if !force_build && executable?(stage2_cached)
        sh_ok("cp " + shq(stage2_cached) + " " + shq(stage2))
        << ""
        << BOLD + "==> Stage 2: cached" + RESET + " " + DIM + "(" + stage2_sha + ")" + RESET
        t2 = clock_ms()
      else
        << ""
        << BOLD + "==> Stage 2: Stage-1 binary compiles tungsten.w" + RESET
        sh_ok("rm -f " + shq(stage2_ll))
        s2_env = toolchain_env_prefix + "TUNGSTEN_LL_DIR=" + shq(stage_ll_dir) + " TUNGSTEN_LL_PATH=" + shq(stage2_ll) + " TUNGSTEN_CLANG_OPT=" + shq(bootstrap_compiler_clang_opt) + " "
        s2_status = sh(s2_env + shq(stage1) + " compile -v " + shq(TUNGSTEN_W) + " --out " + shq(stage2) + STAGE_FLAGS_CMD)
        if s2_status != 0
          eputs(RED + "Stage 2 failed" + RESET + " (exit " + s2_status.to_s + ")")
          exit(1)
        sh_ok("cp " + shq(stage2) + " " + shq(stage2_cached))
        t2 = clock_ms()
        << "    " + DIM + "Stage 2: " + aligned_ms(t2 - t1) + RESET
      << ""

      verify_started = clock_ms()
      verified = same_file_content?(stage1_ll, stage2_ll)
      verify_elapsed = clock_ms() - verify_started
      if verified
        << "    " + GREEN + "VERIFIED" + RESET + " " + DIM + "stage 1 .ll == stage 2 .ll (" + ms(verify_elapsed) + ")" + RESET
      else
        eputs("    " + RED + "WARNING" + RESET + " stage 1 and stage 2 .ll differ!")
        if regular_file?(stage1_ll) && regular_file?(stage2_ll)
          eputs("    " + DIM + "stage 1 .ll: " + file_sha(stage1_ll) + RESET)
          eputs("    " + DIM + "stage 2 .ll: " + file_sha(stage2_ll) + RESET)
        else
          eputs("    " + DIM + "missing emitted .ll for one or both stages" + RESET)

      if pgo_build
        run_pgo_post_step(stage2, "PGO", build_scratch_dir, probe_env_prefix)
      else
        << ""
        install_compiler(stage2, "", true)

# ── Release artifacts (cross / portable) ────────────────────────

artifact_targets = []
artifact_cpus = []
artifact_release_flags = []
if portable_mode
  portable_target = target_triple != "" ? target_triple : (IS_DARWIN ? "x86_64-apple-macos" : "x86_64-unknown-linux-gnu")
  if !portable_target.starts_with?("x86_64-") && !portable_target.starts_with?("x86_64_")
    eputs("--portable is the x86-64 release set; target must be an x86_64 triple")
    exit(1)
  artifact_targets.push(portable_target)
  artifact_cpus.push("x86-64-v2")
  artifact_release_flags.push("1")
  artifact_targets.push(portable_target)
  artifact_cpus.push("x86-64-v3")
  artifact_release_flags.push("1")
elsif target_triple != ""
  artifact_targets.push(target_triple)
  artifact_cpus.push(cpu_name == nil ? "" : cpu_name)
  artifact_release_flags.push(release_mode ? "1" : "0")

-> sanitize_target_label(target)
  out = ""
  i = 0
  while i < target.size
    c = target.slice(i, 1)
    ok = (c >= "A" && c <= "Z") || (c >= "a" && c <= "z") || (c >= "0" && c <= "9") || c == "_" || c == "." || c == "+" || c == "-"
    out = out + (ok ? c : "_")
    i = i + 1
  out

if artifact_targets.size > 0
  << ""
  << BOLD + "==> Release artifacts" + RESET
  ai = 0
  while ai < artifact_targets.size
    artifact_target = artifact_targets[ai]
    artifact_cpu = artifact_cpus[ai]
    artifact_release = artifact_release_flags[ai] == "1"
    cpu_label = artifact_cpu == "" ? "default" : artifact_cpu
    out_dir = ROOT + "/build/releases/" + sanitize_target_label(artifact_target) + "/" + cpu_label
    out_bin = out_dir + "/tungsten-compiler"
    make_dirs(out_dir)
    artifact_flags = ""
    if artifact_release
      artifact_flags = artifact_flags + " --release"
    artifact_flags = artifact_flags + (debug_enabled ? " --debug" : " --no-debug")
    artifact_flags = artifact_flags + " --target " + shq(artifact_target)
    if artifact_cpu != ""
      artifact_flags = artifact_flags + " --cpu " + shq(artifact_cpu)
    if target_sysroot != ""
      artifact_flags = artifact_flags + " --sysroot " + shq(target_sysroot)
    if fast_mode
      artifact_flags = artifact_flags + " --fast"
    art_cmd = "cd " + shq(ROOT) + " && " + probe_env_prefix + "TUNGSTEN_MARCH_ARGS='' " + shq(COMPILER_BIN) + " compile " + shq(TUNGSTEN_W) + " --out " + shq(out_bin) + artifact_flags
    if sh(art_cmd) != 0
      eputs(RED + "Failed to build " + artifact_target + "/" + cpu_label + RESET)
      exit(1)
    if str_has?(artifact_target, "apple")
      if !codesign_ok(out_bin)
        eputs(RED + "Failed to ad-hoc sign " + artifact_target + "/" + cpu_label + RESET)
        exit(1)
    << "    " + GREEN + "built" + RESET + " " + project_relative_path(out_bin)
    ai = ai + 1

# ── Bits ────────────────────────────────────────────────────────

t3 = t_runtime_start
t4 = t_runtime_end

bit_clang_opt = env_or_empty("TUNGSTEN_BITS_CLANG_OPT")
if bit_clang_opt == ""
  bit_clang_opt = release_mode ? "-O3" : "-O0"
if fast_mode && !array_contains?(split_ws(bit_clang_opt), "-ffast-math")
  bit_clang_opt = bit_clang_opt + " -ffast-math"
link_flags = []
link_flags.push(bit_clang_opt)
link_flags.push(debug_enabled ? "-g" : "-DNDEBUG")
link_flags = link_flags + march_flags
link_flags.push(lto_flag)
if IS_DARWIN
  link_flags.push("-Wl,-dead_strip")
else
  link_flags.push("-fuse-ld=lld")
  link_flags.push("-Wl,--gc-sections")
link_libs = []
if tls_flags.size > 0
  link_libs.push("-L" + openssl_prefix + "/lib")
  link_libs.push("-lssl")
  link_libs.push("-lcrypto")
link_libs = link_libs + http2_libs + onig_libs

runtime_dep_shas = []
i = 0
while i < runtime_dependency_files.size
  runtime_dep_shas.push(file_sha(runtime_dependency_files[i]))
  i = i + 1
runtime_key = Digest.sha256(runtime_dep_shas.join(":") + "\n" + join_tab(cc_flags) + "\n" + runtime_cc + "\n" + runtime_ar + "\n" + runtime_ranlib + "\n" + join_tab(link_flags) + "\n" + join_tab(link_libs))

bit_cache_dir = BUILD_CACHE_DIR + "/bits"
make_dirs(bit_cache_dir)

-> bit_build_sha(bit_path, runtime_key_arg, link_flags_arg, link_libs_arg, bit_clang_opt_arg, compiler_flags_arg)
  buf = StringBuffer(1024)
  single = []
  single.push(bit_path)
  buf << tree_sha(single)
  includes = bitfile_includes(bit_path)
  i = 0
  while i < includes.size
    inc = []
    inc.push(includes[i])
    buf << tree_sha(inc)
    i = i + 1
  buf << file_sha(COMPILER_BIN)
  buf << runtime_key_arg
  buf << join_tab(link_flags_arg)
  buf << join_tab(link_libs_arg)
  buf << bit_clang_opt_arg
  buf << join_tab(compiler_flags_arg)
  Digest.sha256(buf.to_s).slice(0, 16)

-> compile_bit(entry, out_bin, bit_clang_opt_arg, toolchain_prefix)
  this_bit_root = dirname_of(dirname_of(entry))
  bit_name = basename_of(this_bit_root)
  build_env = toolchain_prefix + "BIT_HOME=" + shq(ROOT + "/bits") + " TUNGSTEN_CLANG_OPT=" + shq(bit_clang_opt_arg) + " "
  includes = bitfile_includes(this_bit_root)
  if includes.size > 0
    build_env = build_env + "TUNGSTEN_C_INCLUDES=" + shq(includes.join(":")) + " "
  log_path = "/tmp/tungsten-build-" + bit_name + ".log"
  cmd = "cd " + shq(ROOT) + " && " + build_env + shq(COMPILER_BIN) + " compile " + shq(entry) + " --out " + shq(out_bin) + PROGRAM_FLAGS_CMD + " > " + shq(log_path) + " 2>&1"
  ok = sh_ok(cmd)
  if !ok || !regular_file?(out_bin)
    reason = ""
    log = read_file(log_path)
    if log != nil
      log_lines = log.split("\n")
      j = 0
      while j < log_lines.size && reason == ""
        stripped = log_lines[j].strip
        if stripped != ""
          reason = stripped
        j = j + 1
    suffix = reason == "" ? "compilation failed" : "compilation failed: " + reason
    << "    " + DIM + "skip" + RESET + "    " + bit_name + " " + DIM + "(" + suffix + ")" + RESET
    return false
  sh_ok("chmod 755 " + shq(out_bin))
  << "    " + GREEN + "built" + RESET + "   " + project_relative_path(out_bin)
  true

-> bit_short_name(bit_path)
  name = basename_of(bit_path)
  if name.starts_with?("tungsten-")
    return name.slice(9, name.size - 9)
  name

<< ""
t5 = clock_ms()
bits_built = 0
bits_skipped = 0

if skip_bits
  << BOLD + "==> Bits: skipped" + RESET
elsif bit_only
  short_name = bit_short_name(bit_root_found)
  entry = bit_root_found + "/lib/" + short_name + ".w"
  bin_dir = bit_root_found + "/bin"
  make_dirs(bin_dir)
  out_bin = bin_dir + "/" + short_name
  bit_sha = bit_build_sha(bit_root_found, runtime_key, link_flags, link_libs, bit_clang_opt, program_flags)
  stamp = bit_cache_dir + "/" + short_name + ".sha"
  << BOLD + "==> Building " + basename_of(bit_root_found) + RESET
  stamp_content = read_file(stamp)
  stamp_hit = stamp_content != nil && stamp_content.strip == bit_sha
  if !force_build && executable?(out_bin) && stamp_hit
    << "    " + DIM + "skip" + RESET + "    " + project_relative_path(out_bin)
    bits_skipped = 1
  elsif compile_bit(entry, out_bin, bit_clang_opt, toolchain_env_prefix)
    write_file(stamp, bit_sha + "\n")
    bits_built = 1
  else
    exit(1)
else
  << BOLD + "==> Bits: compiling entry points" + RESET
  bit_dirs = capture("find " + shq(ROOT + "/bits") + " -mindepth 1 -maxdepth 1 -type d 2>/dev/null | LC_ALL=C sort").split("\n")
  bi = 0
  while bi < bit_dirs.size
    bit_path = bit_dirs[bi].strip
    bi = bi + 1
    eligible = bit_path != "" && file_directory?(bit_path + "/bin")
    entry = ""
    out_bin = ""
    if eligible
      short_name = bit_short_name(bit_path)
      entry = bit_path + "/lib/" + short_name + ".w"
      out_bin = bit_path + "/bin/" + short_name
      if !regular_file?(entry)
        eligible = false
    if eligible
      short_name = bit_short_name(bit_path)
      bit_sha = bit_build_sha(bit_path, runtime_key, link_flags, link_libs, bit_clang_opt, program_flags)
      stamp = bit_cache_dir + "/" + short_name + ".sha"
      stamp_content = read_file(stamp)
      stamp_hit = stamp_content != nil && stamp_content.strip == bit_sha
      if !force_build && executable?(out_bin) && stamp_hit
        << "    " + DIM + "skip" + RESET + "    " + project_relative_path(out_bin)
        bits_skipped = bits_skipped + 1
      elsif compile_bit(entry, out_bin, bit_clang_opt, toolchain_env_prefix)
        write_file(stamp, bit_sha + "\n")
        bits_built = bits_built + 1
      else
        bits_skipped = bits_skipped + 1

t6 = clock_ms()

if handoff_path != ""
  sh_ok("rm -f " + shq(handoff_path))

# ── Summary ─────────────────────────────────────────────────────

<< ""
if bit_only
  << BOLD + "==> Done" + RESET + " " + DIM + "(runtime " + ms(t4 - t3) + ", compile " + ms(t6 - t5) + ")" + RESET
else
  bits_summary = skip_bits ? "skipped" : bits_built.to_s + " built"
  if bits_skipped > 0
    bits_summary = bits_summary + ", " + bits_skipped.to_s + " skipped"
  << BOLD + "==> Done" + RESET + " " + DIM + "(compiler " + ms(t2 - t0) + ", runtime " + ms(t4 - t3) + ", bits: " + bits_summary + " " + ms(t6 - t5) + ")" + RESET
<< ""
