require "tmpdir"
require "fileutils"
require "digest"
require "find"
require "etc"

# Compiler source directory. Override via `--compiler-dir <name>`
# (or the TUNGSTEN_COMPILER env var) to bootstrap from an alternate
# tree — useful when iterating on a parallel compiler rewrite.
compiler_dir_arg_idx = ARGV.index("--compiler-dir")
if compiler_dir_arg_idx
  COMPILER_DIR_NAME = ARGV[compiler_dir_arg_idx + 1]
  ARGV.delete_at(compiler_dir_arg_idx + 1)
  ARGV.delete_at(compiler_dir_arg_idx)
else
  COMPILER_DIR_NAME = ENV.fetch("TUNGSTEN_COMPILER", "compiler")
end
TUNGSTEN_W   = File.join(ROOT, COMPILER_DIR_NAME, "tungsten.w")
GEM_EXE      = File.join(ROOT, "implementations/ruby/exe/ruby-tungsten")
GEMFILE      = File.join(ROOT, "implementations/ruby/Gemfile")
COMPILER_BIN = File.join(ROOT, "bin/tungsten-compiler")
RUNTIME_DIR  = File.join(ROOT, "runtime")
CUSTOM_RUBY  = File.join(ROOT, "src/patched/ruby/ruby")

if ARGV.include?("--help") || ARGV.include?("-h")
  puts <<~HELP
    Usage: tungsten build [options]

    Bootstrap the self-hosted Tungsten compiler and build bit entry points.
    Default bootstrap: implementations/c (the C bytecode VM).

    Options:
      -1          Build and install only the stage-1 compiler
      -2          Reuse the existing stage-1 binary and build stage 2
      --force     Ignore cached stage binaries and rebuild
      --pgo       Build the compiler with profile-guided optimization
      --no-bits   Skip compiling bit entry points (implied by -0, -1, and -2)
      -h, --help  Show this help

    Developer options (bootstrap maintainers; not needed day-to-day):
      -0          Build only the Spinel stage-0 compiler (implies --spinel)
      --spinel    Bootstrap stage 1 via Spinel stage-0 instead of the C VM
      --ruby      Bootstrap stage 1 via the Ruby interpreter
                  (or set TUNGSTEN_BOOTSTRAP=ruby|spinel)
  HELP
  exit 0
end

# Preflight: fail fast with friendly, per-tool guidance if a required build tool
# is missing, instead of a cryptic make/clang error dump partway through the
# bootstrap. Uses Tungsten::Doctor.build_preflight (a self-contained check that
# needs no gem internals). Run `bin/tungsten doctor` for the full toolchain report.
require File.join(ROOT, "implementations/ruby/lib/tungsten/doctor")
build_missing = Tungsten::Doctor.build_preflight
unless build_missing.empty?
  pf_color = $stderr.tty? && !ENV["NO_COLOR"]
  pf_red   = pf_color ? "\e[91m" : ""
  pf_bold  = pf_color ? "\e[1m"  : ""
  pf_dim   = pf_color ? "\e[2m"  : ""
  pf_reset = pf_color ? "\e[0m"  : ""
  $stderr.puts "#{pf_bold}#{pf_red}✗ Cannot build — missing required tool(s):#{pf_reset}"
  build_missing.each do |name, hint|
    $stderr.puts "  #{pf_red}#{name}#{pf_reset} — install with:"
    $stderr.puts "    #{pf_dim}#{hint}#{pf_reset}"
  end
  $stderr.puts
  $stderr.puts "Then re-run #{pf_bold}bin/tungsten build#{pf_reset}. Full check: #{pf_bold}bin/tungsten doctor#{pf_reset}."
  exit 1
end

ENV["BUNDLE_GEMFILE"] = GEMFILE
ENV["TUNGSTEN_CACHE_DIR"] = File.join(ROOT, "build/cache")

if ARGV.include?("--ruby-bootstrap")
  $stderr.puts "--ruby-bootstrap has been renamed to --ruby"
  exit 1
end

ruby_bootstrap_requested = !!ARGV.delete("--ruby") || ENV["TUNGSTEN_BOOTSTRAP"] == "ruby"
spinel_requested = !!ARGV.delete("--spinel") || ENV["TUNGSTEN_BOOTSTRAP"] == "spinel"
stage0_only = ARGV.include?("-0")
stage1_only = ARGV.include?("-1")
stage2_only = ARGV.include?("-2")
pgo_build   = ARGV.include?("--pgo")
force_build = ARGV.include?("--force")
skip_bits_requested = ARGV.include?("--no-bits")

# -0 (Spinel stage0) only makes sense in Spinel mode. Auto-promote.
spinel_requested = true if stage0_only

C_INTERP = File.join(ROOT, "implementations/c/build/tungsten-c")
C_INTERP_DIR = File.join(ROOT, "implementations/c")

SPINEL_BIN     = File.join(ROOT, "src/patched/spinel/spinel")
SPINEL_RUNTIME = File.join(ROOT, "src/patched/spinel/lib/libspinel_rt.a")
spinel_available = File.executable?(SPINEL_BIN) && File.file?(SPINEL_RUNTIME)

if ruby_bootstrap_requested && spinel_requested
  warn "--ruby and --spinel are mutually exclusive — using --spinel"
  ruby_bootstrap_requested = false
end

# Resolve which bootstrap path to take. Default is the C VM
# (implementations/c/build/tungsten-c) — fastest, no separate Spinel
# install needed. --spinel opts into the precompiled spinel stage0
# path. --ruby (or TUNGSTEN_BOOTSTRAP=ruby) is the legacy
# pure-Ruby fallback. PGO also forks off into the Ruby path because
# the PGO instrumentation lives there.
if spinel_requested && !spinel_available
  $stderr.puts "Spinel not found at #{SPINEL_BIN} — `--spinel` requested but unavailable. Run `rake deps` to install Spinel."
  exit 1
end

use_spinel_bootstrap = spinel_requested
use_c_bootstrap = !ruby_bootstrap_requested && !spinel_requested && !pgo_build

build_cache_dir = File.join(ROOT, "build/cache")
FileUtils.mkdir_p(build_cache_dir)

# Per-invocation scratch root. Every intermediate build artifact that
# isn't the persistent, content-hash-keyed cache (build/cache/*) lives
# under here, PID-scoped, so two `bin/tungsten build`s running at once
# (routine with several agent sessions attached to one checkout) can't
# clobber each other's in-flight stage1/stage2 output or emitted .ll —
# that collision previously showed up as a spurious "stage 1 .ll !=
# stage 2 .ll" mismatch, or a crash from one process linking against
# the other's mid-write intermediate state. Clear a path left by a crashed
# process before reuse: PIDs eventually wrap, and compiler freshness checks
# must never accept another invocation's old output.
build_scratch_dir = "/tmp/tungsten-build-#{Process.pid}"
FileUtils.rm_rf(build_scratch_dir)
FileUtils.mkdir_p(build_scratch_dir)

FILE_DIGEST_CACHE_PATH = File.join(build_cache_dir, "file-digests.marshal")
$file_digest_cache =
  begin
    cache = File.file?(FILE_DIGEST_CACHE_PATH) ? Marshal.load(File.binread(FILE_DIGEST_CACHE_PATH)) : {}
    cache.is_a?(Hash) ? cache : {}
  rescue StandardError
    {}
  end
$file_digest_cache_dirty = false

# Cache for results of expensive `brew`/`pkg-config` shell-outs. Keyed on
# a fingerprint of marker files (existence + mtime); on a cache hit we
# avoid 60-70ms of subprocess setup per build. Invalidates when the user
# installs/uninstalls a homebrew package (the marker file mtime moves).
SYSTEM_DEPS_CACHE_PATH = File.join(build_cache_dir, "system-deps.marshal")
$system_deps_cache =
  begin
    cache = File.file?(SYSTEM_DEPS_CACHE_PATH) ? Marshal.load(File.binread(SYSTEM_DEPS_CACHE_PATH)) : {}
    cache.is_a?(Hash) ? cache : {}
  rescue StandardError
    {}
  end
$system_deps_cache_dirty = false

at_exit do
  if $file_digest_cache_dirty
    FileUtils.mkdir_p(File.dirname(FILE_DIGEST_CACHE_PATH))
    tmp = "#{FILE_DIGEST_CACHE_PATH}.#{$$}.tmp"
    File.binwrite(tmp, Marshal.dump($file_digest_cache))
    FileUtils.mv(tmp, FILE_DIGEST_CACHE_PATH)
  end
  if $system_deps_cache_dirty
    FileUtils.mkdir_p(File.dirname(SYSTEM_DEPS_CACHE_PATH))
    tmp = "#{SYSTEM_DEPS_CACHE_PATH}.#{$$}.tmp"
    File.binwrite(tmp, Marshal.dump($system_deps_cache))
    FileUtils.mv(tmp, SYSTEM_DEPS_CACHE_PATH)
  end
end

# Memoise an expensive system-probe result. The fingerprint is built
# from a list of marker paths — existence + mtime is enough to catch a
# `brew install` / `brew uninstall` (which moves the symlink mtime) and
# new pkg-config files appearing. The block is only re-run when the
# fingerprint changes.
def cached_system_deps(name, marker_paths, &block)
  common_markers = %w[
    /opt/homebrew/include /opt/homebrew/lib /opt/homebrew/lib/pkgconfig
    /usr/local/include /usr/local/lib /usr/local/lib/pkgconfig
    /usr/local/share/pkgconfig /usr/include /usr/include/zstd.h
    /usr/include/oniguruma.h /usr/lib /usr/lib/pkgconfig
    /usr/share/pkgconfig
  ] + Dir["/usr/lib/*/pkgconfig", "/usr/lib/*/pkgconfig/*.pc"]
  path_fingerprint = (marker_paths + common_markers).uniq.map do |path|
    if File.exist?(path)
      stat = File.stat(path)
      "#{path}:#{stat.mtime.to_i}:#{stat.mtime.nsec}"
    else
      "#{path}:missing"
    end
  end.join("|")
  probe_environment = %w[PATH PKG_CONFIG_PATH PKG_CONFIG_LIBDIR HOMEBREW_PREFIX].map do |key|
    "#{key}=#{ENV[key]}"
  end.join("|")
  fingerprint = [path_fingerprint, probe_environment,
                 tool_identity("pkg-config"), tool_identity("brew")].join("|")

  entry = $system_deps_cache[name]
  return entry[:value] if entry && entry[:fingerprint] == fingerprint

  value = block.call
  $system_deps_cache[name] = { fingerprint: fingerprint, value: value }
  $system_deps_cache_dirty = true
  value
end

def file_sha(path)
  full = File.expand_path(path)
  return "missing:#{path}" unless File.file?(full)

  stat = File.stat(full)
  # ctime/inode close the same-size, restored-mtime hole without giving up the
  # fast digest cache on the common unchanged-input path.
  sig = [stat.size, stat.mtime.to_i, stat.mtime.nsec,
         stat.ctime.to_i, stat.ctime.nsec, stat.ino]
  entry = $file_digest_cache[full]
  if entry && entry.first(sig.size) == sig
    return entry[sig.size]
  end

  digest = Digest::SHA256.file(full).hexdigest
  $file_digest_cache[full] = sig + [digest]
  $file_digest_cache_dirty = true
  digest
end

def atomic_copy(source, destination)
  tmp = "#{destination}.#{$$}.tmp"
  FileUtils.cp(source, tmp)
  FileUtils.mv(tmp, destination)
ensure
  FileUtils.rm_f(tmp) if defined?(tmp) && tmp
end

def atomic_write(contents, destination)
  tmp = "#{destination}.#{$$}.tmp"
  File.binwrite(tmp, contents)
  FileUtils.mv(tmp, destination)
ensure
  FileUtils.rm_f(tmp) if defined?(tmp) && tmp
end

def resolve_executable(command)
  return command if command.include?(File::SEPARATOR)

  ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).each do |dir|
    candidate = File.join(dir, command)
    return candidate if File.executable?(candidate) && !File.directory?(candidate)
  end

  command
end

def sibling_tool(command, tool)
  candidate = File.join(File.dirname(resolve_executable(command)), tool)
  File.executable?(candidate) ? candidate : nil
end

def tool_identity(command)
  path = resolve_executable(command)
  full = File.expand_path(path)
  stat = File.stat(full)
  [full, stat.size, stat.mtime.to_i, stat.mtime.nsec].join(":")
rescue StandardError
  path
end

TOOLCHAIN_ENV_KEYS = %w[
  SDKROOT MACOSX_DEPLOYMENT_TARGET CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH
  LIBRARY_PATH PKG_CONFIG_PATH PKG_CONFIG_LIBDIR
].freeze

def ambient_toolchain_identity
  TOOLCHAIN_ENV_KEYS.map { |key| "#{key}=#{ENV[key]}" }.join("\0")
end

# ── Stage 0 (C VM): hash-based source cache ─────────────────────
#
# Hash every source the C VM build depends on. Source/header content,
# Makefile (compile flags live there), and the shared runtime/wvalue.h
# all participate so any edit forces a rebuild — unlike `File.executable?`
# which kept stale binaries alive across source changes.
c_vm_dependency_files = -> {
  files = Dir[File.join(C_INTERP_DIR, "src/*.c"),
              File.join(C_INTERP_DIR, "src/*.inc"),
              File.join(C_INTERP_DIR, "include/*.h"),
              File.join(C_INTERP_DIR, "Makefile")]
  files << File.join(RUNTIME_DIR, "wvalue.h")
  files << File.join(RUNTIME_DIR, "w_lexchar_cache.c")
  files.uniq.sort
}

c_vm_build_key = -> {
  dependency_key = Digest::SHA256.new
  c_vm_dependency_files.call.each do |path|
    dependency_key.update(path.delete_prefix(ROOT + "/"))
    dependency_key.update("\0")
    dependency_key.update(file_sha(path))
    dependency_key.update("\0")
  end
  cc = ENV["CC"].to_s.empty? ? "clang" : ENV["CC"]
  make_assignments = ENV.fetch("MAKEFLAGS", "").split.select do |part|
    part.include?("=") && !part.start_with?("--jobserver")
  end.sort.join("\0")
  Digest::SHA256.hexdigest([
    dependency_key.hexdigest,
    RUBY_PLATFORM,
    tool_identity(cc),
    ENV["CC"].to_s,
    ENV["CFLAGS"].to_s,
    ENV["CPPFLAGS"].to_s,
    ENV["ARCH_FLAGS"].to_s,
    ENV["LDFLAGS"].to_s,
    ambient_toolchain_identity,
    make_assignments
  ].join("\n"))
}

c_vm_make_args = lambda do
  # Let an explicit MAKEFLAGS jobserver win. Otherwise cap at eight: this
  # C VM has fourteen translation units and measurements flatten after -j8.
  makeflags = ENV.fetch("MAKEFLAGS", "")
  next [] if makeflags.match?(/(?:^|\s)(?:-j|--jobs)/)

  requested = ENV.fetch("TUNGSTEN_BUILD_JOBS", Etc.nprocessors.to_s).to_i
  requested = 1 if requested < 1
  ["-j", [requested, 8].min.to_s]
end

# Build the C VM in a per-process object directory, then atomically publish its
# binary into the identity cache. Concurrent misses never share writable files.
# Returns [:cached|:built, elapsed_seconds, identity_binary, identity_key].
ensure_c_interp = lambda do
  key = c_vm_build_key.call
  cached_build_dir = File.join("build", "identity-#{key}")
  cached_binary = File.join(C_INTERP_DIR, cached_build_dir, "tungsten-c")
  scratch_build_dir = "#{cached_build_dir}-build-#{Process.pid}"
  scratch_binary = File.join(C_INTERP_DIR, scratch_build_dir, "tungsten-c")
  identity_binary = cached_binary
  verb = :cached
  elapsed = 0.0

  if force_build || !File.executable?(cached_binary)
    t_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    log_path = File.join(Dir.tmpdir, "tungsten-c-vm-build-#{Process.pid}.log")
    FileUtils.rm_rf(File.join(C_INTERP_DIR, scratch_build_dir))
    unless system("make", "-B", *c_vm_make_args.call, "-C", C_INTERP_DIR,
                  "BUILD_DIR=#{scratch_build_dir}", [:out, :err] => log_path)
      $stderr.puts File.read(log_path) if File.exist?(log_path)
      FileUtils.rm_rf(File.join(C_INTERP_DIR, scratch_build_dir))
      $stderr.puts "Failed to build implementations/c (make -C #{C_INTERP_DIR})"
      exit 1
    end
    verb = :built
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t_start
    FileUtils.mkdir_p(File.dirname(cached_binary))
    atomic_copy(scratch_binary, cached_binary)
    FileUtils.chmod(0o755, cached_binary)
    FileUtils.rm_rf(File.join(C_INTERP_DIR, scratch_build_dir))
  end

  unless File.executable?(identity_binary)
    $stderr.puts "C VM build produced no executable at #{identity_binary}"
    exit 1
  end
  # Keep the conventional path useful for direct developer invocations. This
  # is an atomic convenience publication; the build itself uses identity_binary.
  unless same_file_content?(identity_binary, C_INTERP)
    atomic_copy(identity_binary, C_INTERP)
    FileUtils.chmod(0o755, C_INTERP)
  end
  [verb, elapsed, identity_binary, key]
end

# Phase 6: LTO mode for runtime compile + link.
#   default:    -flto=thin   — bitcode + summary-based imports; fast link;
#                              lets LTO see into runtime functions (w_method_call,
#                              w_array_get, etc.) for partial cross-optimization.
#   --release:  -flto=full   — single LLVM module; strongest optimization;
#                              ~30% slower link, marginal further perf gain.
release_mode = ARGV.include?("--release")
ARGV.delete("--release")
LTO_FLAG = release_mode ? "-flto=full" : "-flto=thin"

# Optimization flag threaded into the bootstrap stage compiles. Both --release
# and --native emit identical .ll (both skip debug checks + stacktrace metadata),
# so the stage1==stage2 byte-identity check holds either way — they differ only
# in the clang -march the stage binaries are linked with. A normal local build
# uses --native (host-tuned, fast); a release build (`bin/tungsten build
# --release`) uses --release (portable x86-64-v2 / armv8-a baseline) so the
# distributed compiler binary runs on CPUs older than the build machine.
STAGE_OPT_FLAG = release_mode ? "--release" : "--native"

# ISA/tuning flags for the runtime .o compile, from the shared BuildFlags source
# (mirrors compiler/tungsten.w's march_flags). Portable only for a release build;
# host-tuned (native) for a normal local build.
require File.join(ROOT, "implementations/ruby/lib/tungsten/build_flags")
# For a release build the ISA/tuning comes from BuildFlags (portable x86-64-v2 /
# armv8-a), UNLESS the environment already pins TUNGSTEN_MARCH_ARGS — which lets
# the release CI build extra tiers (e.g. -march=x86-64-v3) without a code change.
# Local (native) builds leave it unset → host-tuned native.
MARCH_FLAGS =
  if release_mode && !ENV["TUNGSTEN_MARCH_ARGS"].to_s.empty?
    ENV["TUNGSTEN_MARCH_ARGS"].split
  else
    Tungsten::BuildFlags.march(release_mode ? :portable : :native)
  end
# Hand it to the stage compiles via env so the stage-0 C VM (which can't ccall
# setenv) bakes the same baseline into the target-features probe + link.
ENV["TUNGSTEN_MARCH_ARGS"] ||= MARCH_FLAGS.join(" ") if release_mode

color = $stderr.tty? && !ENV["NO_COLOR"]
bold  = color ? "\e[1m" : ""
dim   = color ? "\e[2m" : ""
green = color ? "\e[32m" : ""
red   = color ? "\e[31m" : ""
reset = color ? "\e[0m" : ""

def ms(seconds)
  "#{(seconds * 1000).round}ms"
end

def aligned_ms(seconds)
  format("%6s", ms(seconds))
end

# Install through a content-addressed signed cache. This makes the requested
# live compiler directly comparable to a stable artifact (no separate stamp
# can lie after bootstrap.sh or another build replaces the live binary).
install_compiler = lambda do |src, label = nil, announce: true|
  sidemap = "#{src}.sidemap"
  install_sha = Digest::SHA256.hexdigest([
    file_sha(src),
    File.exist?(sidemap) ? file_sha(sidemap) : "missing:sidemap"
  ].join(":"))
  install_cache_dir = File.join(ROOT, "build/cache/compiler-installs")
  FileUtils.mkdir_p(install_cache_dir)
  signed_cache = File.join(install_cache_dir, install_sha)
  signed_sidemap_cache = "#{signed_cache}.sidemap"
  installed_sidemap = "#{COMPILER_BIN}.sidemap"

  unless File.executable?(signed_cache) && optional_cache_complete?(signed_sidemap_cache)
    tmp_cache = "#{signed_cache}.#{Process.pid}.tmp"
    FileUtils.cp(src, tmp_cache)
    FileUtils.chmod(0o755, tmp_cache)
    if RUBY_PLATFORM =~ /darwin/
      unless system("codesign", "--force", "-s", "-", tmp_cache, out: File::NULL, err: File::NULL)
        $stderr.puts "#{red}codesign failed for #{COMPILER_BIN}#{reset}"
        FileUtils.rm_f(tmp_cache)
        exit 1
      end
    end
    FileUtils.mv(tmp_cache, signed_cache)
    publish_optional_file(sidemap, signed_sidemap_cache)
  end

  sidemap_matches = if File.file?(signed_sidemap_cache)
                      same_file_content?(signed_sidemap_cache, installed_sidemap)
                    else
                      !File.exist?(installed_sidemap)
                    end
  if File.executable?(COMPILER_BIN) && same_file_content?(signed_cache, COMPILER_BIN) && sidemap_matches
    next
  end

  atomic_copy(signed_cache, COMPILER_BIN)
  FileUtils.chmod(0o755, COMPILER_BIN)
  restore_optional_file(signed_sidemap_cache, installed_sidemap)
  if announce
    suffix = label ? " #{dim}(#{label})#{reset}" : ""
    puts "    #{green}installed#{reset} #{COMPILER_BIN}#{suffix}"
  end
end

platform_event_src =
  if RUBY_PLATFORM =~ /darwin/
    "event_kqueue.c"
  elsif RUBY_PLATFORM =~ /linux/
    ENV["USE_IOURING"] ? "event_iouring.c" : "event_epoll.c"
  end

# ── Detect if we're inside a bit directory ──────────────────────

def find_bit_root(dir)
  # Walk up looking for a Bitfile
  d = File.expand_path(dir)
  while d != "/"
    return d if File.exist?(File.join(d, "Bitfile"))
    d = File.dirname(d)
  end
  nil
end

def bitfile_includes(bit_root)
  bitfile = File.join(bit_root, "Bitfile")
  return [] unless File.exist?(bitfile)

  text = File.read(bitfile).each_line.map { |line| line.sub(/\s+#.*\z/, "") }.join("\n")
  includes = []

  text.scan(/\binclude\s+["']([^"']+)["']/) do |match|
    includes << File.expand_path(match.first, bit_root)
  end

  text.scan(/\bincludes\s+\[(.*?)\]/m) do |match|
    match.first.scan(/["']([^"']+)["']/) do |path|
      includes << File.expand_path(path.first, bit_root)
    end
  end

  includes.uniq
end

def onig_flags
  cached_system_deps("onig_flags", [
    "/opt/homebrew/include/oniguruma.h",
    "/opt/homebrew/lib/libonig.dylib",
    "/opt/homebrew/lib/libonig.a"
  ]) do
    cflags = `pkg-config --cflags oniguruma 2>/dev/null`.split
    libs = `pkg-config --libs oniguruma 2>/dev/null`.split

    if cflags.empty? && File.exist?("/opt/homebrew/include/oniguruma.h")
      cflags = ["-I/opt/homebrew/include"]
    end

    if libs.empty?
      if File.exist?("/opt/homebrew/lib/libonig.dylib") || File.exist?("/opt/homebrew/lib/libonig.a")
        libs = ["-L/opt/homebrew/lib", "-lonig"]
      elsif cflags.any?
        libs = ["-lonig"]
      end
    end

    cflags << "-DTUNGSTEN_ONIG" if cflags.any?
    [cflags, libs]
  end
end

bit_root = find_bit_root(Dir.pwd)
bit_only = bit_root && bit_root != ROOT
skip_bits = skip_bits_requested || (!bit_only && (stage0_only || stage1_only || stage2_only))

# ── Helper: compile a .w entry point to a native binary ─────────

def project_relative_path(path)
  full = File.expand_path(path)
  full.delete_prefix("#{ROOT}/")
end

def compile_bit(entry, out_bin, compiler, gem_exe, tungsten_w, runtime_archive, link_flags, link_libs, bit_clang_opt,
                toolchain_env, colors)
  bold, dim, green, red, reset = colors
  bit_root = File.dirname(File.dirname(entry))
  bit_name = File.basename(bit_root)
  build_env = toolchain_env.merge(
    "BIT_HOME" => File.join(ROOT, "bits"),
    "TUNGSTEN_CLANG_OPT" => bit_clang_opt
  )
  includes = bitfile_includes(bit_root)
  if includes.any?
    build_env["TUNGSTEN_C_INCLUDES"] = includes.join(File::PATH_SEPARATOR)
  end

  # Run from repo root so the compiler finds runtime/
  log_path = File.join(Dir.tmpdir, "tungsten-build-#{bit_name}.log")
  ok = Dir.chdir(ROOT) do
    if File.executable?(compiler)
      system(build_env, compiler, "compile", entry, "--out", out_bin, [:out, :err] => log_path)
    else
      system(build_env, gem_exe, tungsten_w, "--", "compile", entry, "--out", out_bin, [:out, :err] => log_path)
    end
  end

  unless ok && File.exist?(out_bin)
    reason = nil
    if File.exist?(log_path)
      reason = File.readlines(log_path, chomp: true).map(&:strip).find { |line| !line.empty? }
    end
    suffix = reason ? "compilation failed: #{reason}" : "compilation failed"
    puts "    #{dim}skip#{reset}    #{bit_name} #{dim}(#{suffix})#{reset}"
    return false
  end

  FileUtils.chmod(0o755, out_bin)
  puts "    #{green}built#{reset}   #{project_relative_path(out_bin)}"
  true
end

# ── --force: bypass persistent cache hits ────────────────────────
# Every force-aware phase rebuilds into PID/identity-scoped temporary output
# and atomically publishes the result. Do not delete shared content-addressed
# caches here: another concurrent build may be reading them, and identity keys
# already prevent stale artifacts from masquerading as current output.
if force_build
  FileUtils.rm_rf(build_scratch_dir)
  FileUtils.mkdir_p(build_scratch_dir)
  puts "#{dim}--force: rebuilding all requested phases#{reset}"
end

# ── Runtime: compile C sources first (needed by Stage 1 linker) ───

puts
puts "#{bold}==> Runtime: compiling C sources#{reset}"
t_runtime_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

tls_enabled = ENV["TLS"] || ENV["TUNGSTEN_TLS"]
runtime_srcs = %w[runtime.c ssmr_witness.c lexchar_tables.c tls_stub.c aks.c slab_zstd.c]
runtime_srcs << platform_event_src if platform_event_src
runtime_srcs << "tls.c" if tls_enabled
metal_enabled = RUBY_PLATFORM =~ /darwin/
runtime_srcs << "metal.m" if metal_enabled
runtime_srcs << "blas_bridge.c" if RUBY_PLATFORM.include?("darwin")  # real Accelerate BLAS for the compiler binary
# hid_bridge.m: the compiler binary's REPL scrub loop calls w_hid_streamdeck_*
# (Stream Deck + dials), so those symbols must be in the runtime archive that
# stage 1/2 link against. (graphics.m stays out — the compiler draws no windows.)
runtime_srcs << "hid_bridge.m" if metal_enabled

openssl_prefix = cached_system_deps("openssl_prefix", [
  "/opt/homebrew/opt/openssl@3",
  "/opt/homebrew/bin/brew"
]) do
  (`brew --prefix openssl@3 2>/dev/null`.strip rescue "") || ""
end
openssl_prefix = "/opt/homebrew/opt/openssl@3" if openssl_prefix.empty?
tls_flags = tls_enabled && File.exist?("#{openssl_prefix}/include/openssl/ssl.h") ?
  ["-DTUNGSTEN_TLS", "-I#{openssl_prefix}/include"] : []

nghttp2_prefix = "/opt/homebrew/opt/libnghttp2"
http2_flags = File.exist?("#{nghttp2_prefix}/include/nghttp2/nghttp2.h") ?
  ["-DTUNGSTEN_HTTP2", "-I#{nghttp2_prefix}/include"] : []

onig_cflags, onig_libs = onig_flags

runtime_cc = ENV["TUNGSTEN_CC"].to_s
runtime_cc = "clang" if runtime_cc.empty?
runtime_ar = ENV["TUNGSTEN_AR"].to_s
runtime_ar = sibling_tool(runtime_cc, "llvm-ar") || "ar" if runtime_ar.empty?
runtime_ranlib = ENV["TUNGSTEN_RANLIB"].to_s
runtime_ranlib = sibling_tool(runtime_cc, "llvm-ranlib").to_s if runtime_ranlib.empty?
compiler_toolchain_env = {
  "TUNGSTEN_CC" => runtime_cc,
  "TUNGSTEN_AR" => runtime_ar
}
compiler_toolchain_env["TUNGSTEN_RANLIB"] = runtime_ranlib unless runtime_ranlib.empty?

# zstd is needed for the static-slab string interner. The compiler
# emits w_zstd_compress_llvm_escaped + w_slab_init_static_zstd calls
# even with --intern raw (the slab is always present; the algorithm
# choice picks how it's loaded). slab_zstd.c includes <zstd.h> and the
# final binary needs to link -lzstd from /opt/homebrew/lib.
zstd_cflags, zstd_libs = cached_system_deps("zstd_flags", [
  "/opt/homebrew/include/zstd.h",
  "/opt/homebrew/lib/libzstd.dylib",
  "/opt/homebrew/lib/libzstd.a"
]) do
  cflags = `pkg-config --cflags libzstd 2>/dev/null`.split
  libs   = `pkg-config --libs libzstd 2>/dev/null`.split
  if cflags.empty? && File.exist?("/opt/homebrew/include/zstd.h")
    cflags = ["-I/opt/homebrew/include"]
  end
  if libs.empty?
    if File.exist?("/opt/homebrew/lib/libzstd.dylib") || File.exist?("/opt/homebrew/lib/libzstd.a")
      libs = ["-L/opt/homebrew/lib", "-lzstd"]
    elsif cflags.any?
      libs = ["-lzstd"]
    end
  end
  # Linux: zstd lives on default paths (libzstd-dev) — no -I/-L needed,
  # but the link still requires -lzstd. Without this the compiler emits
  # zstd slab-init calls (the empty-but-set env reads as "available")
  # while the link lacks the library: undefined ZSTD_isError at stage 1.
  if libs.empty? && RUBY_PLATFORM =~ /linux/ &&
     (File.exist?("/usr/include/zstd.h") || Dir.glob("/usr/lib/*/libzstd.so*").any?)
    libs = ["-lzstd"]
  end
  [cflags, libs]
end

# Stage 1 and stage 2 both link this archive with --no-lto. Keeping LLVM
# bitcode here made clang reprocess the runtime during each supposedly
# no-LTO link; native objects cut several seconds while preserving emitted IR.
# Bit entry points still use LTO_FLAG independently in link_flags below.
runtime_cache_schema = "runtime-cache-v1"
cc_flags = %W[-O2 -DNDEBUG -pthread] + MARCH_FLAGS + %w[-c] + tls_flags + http2_flags + onig_cflags + zstd_cflags
runtime_objc_flags = %W[-O2 -DNDEBUG] + MARCH_FLAGS + %w[-c -x objective-c]
# Linux (validated on Ubuntu 24.04): without _DEFAULT_SOURCE, popen/pclose
# prototypes are hidden under strict feature-test macros and the implicit
# declarations segfault the stage-0 C VM at runtime.
cc_flags << "-D_DEFAULT_SOURCE" if RUBY_PLATFORM =~ /linux/
# w_lexchar_cache.c is #included by runtime.c (not compiled separately), so it
# must be in the HASH inputs or edits to it never invalidate the cached runtime.
runtime_dependency_files = (runtime_srcs.map { |src| File.join(RUNTIME_DIR, src) } +
                            Dir[File.join(RUNTIME_DIR, "*.h")] +
                            [File.join(RUNTIME_DIR, "w_lexchar_cache.c"),
                             File.join(RUNTIME_DIR, "w_char_table.c"),
                             File.join(RUNTIME_DIR, "generated/bigint_thresholds.h")]).uniq.sort

# Pass the already-cached system-probe results to the compiler so it
# doesn't have to re-run `capture("pkg-config ...")` etc. on every stage.
# Each capture() is fork+exec+pipe at ~10-30ms; the compiler does 9 of
# them, totalling ~90-270ms per stage. Driving compiler/tungsten.w via
# these env vars short-circuits the probes — the compiler treats an
# empty string as "resolved to no flags", and falls back to capture()
# only when the var is unset (i.e. the compiler was run outside this
# build script).
compiler_probe_env = {
  "TUNGSTEN_ZSTD_CFLAGS"  => zstd_cflags.join(" "),
  "TUNGSTEN_ZSTD_LDFLAGS" => zstd_libs.join(" "),
  "TUNGSTEN_ONIG_CFLAGS"  => onig_cflags.join(" "),
  "TUNGSTEN_ONIG_LDFLAGS" => onig_libs.join(" "),
  "TUNGSTEN_OS"           => (RUBY_PLATFORM =~ /darwin/ ? "Darwin" :
                              RUBY_PLATFORM =~ /linux/ ? "Linux" : "")
}.merge(compiler_toolchain_env)

# This only controls the optimization level used to link the bootstrap
# compiler binary itself. Programs compiled by that binary still use the
# compiler's normal link defaults unless the caller sets TUNGSTEN_CLANG_OPT.
#
# `--release` implies the full optimization stack: -O3 + -flto=full (already
# wired via LTO_FLAG). The -march/-mtune choice is added by the compiler's own
# link_binary (from march_flags), so this only carries the -O level; the caller
# can still override the whole thing via TUNGSTEN_CLANG_OPT.
release_default_opt = "-O3"
bootstrap_compiler_clang_opt =
  if !ENV["TUNGSTEN_CLANG_OPT"].to_s.empty?
    ENV["TUNGSTEN_CLANG_OPT"]
  elsif release_mode
    release_default_opt
  else
    "-O0"
  end

runtime_dependencies_key = Digest::SHA256.new
runtime_dependency_files.each do |path|
  runtime_dependencies_key.update(path.delete_prefix(ROOT + "/"))
  runtime_dependencies_key.update("\0")
  runtime_dependencies_key.update(file_sha(path))
  runtime_dependencies_key.update("\0")
end
runtime_compile_key = Digest::SHA256.hexdigest([
  runtime_cache_schema,
  runtime_dependencies_key.hexdigest,
  cc_flags.join("\0"),
  runtime_objc_flags.join("\0"),
  RUBY_PLATFORM,
  tool_identity(runtime_cc),
  tool_identity(runtime_ar),
  ambient_toolchain_identity
].join("\n"))
runtime_archive = File.join(build_cache_dir, "runtime-#{runtime_compile_key}.a")
runtime_env_contents = [
  "runtime-env-v1",
  zstd_cflags.join(" "), zstd_libs.join(" "),
  onig_cflags.join(" "), onig_libs.join(" "),
  compiler_probe_env.fetch("TUNGSTEN_OS"), runtime_cc, runtime_ar, runtime_ranlib
].join("\n") + "\n"
runtime_env_key = Digest::SHA256.hexdigest(runtime_env_contents)
runtime_env_manifest = File.join(build_cache_dir, "runtime-env-#{runtime_env_key}.env")
runtime_current_manifest = File.join(build_cache_dir, "runtime-current.manifest")

if !force_build && File.file?(runtime_archive)
  t_runtime_cached = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  puts "    #{green}CACHED#{reset} runtime #{dim}#{aligned_ms(t_runtime_cached - t_runtime_start)}#{reset}"
else
  Dir.mktmpdir("tungsten-runtime") do |dir|
    compile_jobs = runtime_srcs.map do |src|
      Thread.new do
        src_path = File.join(RUNTIME_DIR, src)
        obj_path = File.join(dir, File.basename(src, File.extname(src)) + ".o")
        flags = cc_flags
        # metal.m is Obj-C — use the Obj-C frontend and skip flags clang
        # rejects on `.m` files (e.g. -mtune=native isn't an issue but
        # several C-only diagnostic flags would be).
        if src.end_with?(".m")
          flags = runtime_objc_flags
        end
        [src, obj_path, system(runtime_cc, *flags, src_path, "-o", obj_path)]
      end
    end
    compiled = compile_jobs.map(&:value)
    failed = compiled.find { |(_src, _obj, ok)| !ok }
    if failed
      $stderr.puts "#{red}Failed to compile #{failed[0]}#{reset}"
      exit 1
    end
    objs = compiled.map { |(_src, obj, _ok)| obj }
    # Archive + index into a per-invocation temp path first, then atomically
    # publish the immutable, content-addressed archive. Different worktrees
    # no longer share /tmp/tungsten-runtime.a, and concurrent configurations
    # cannot mismatch a mutable payload with a separate stamp.
    tmp_archive = File.join(dir, File.basename(runtime_archive))
    unless system(runtime_ar, "rcs", tmp_archive, *objs)
      $stderr.puts "#{red}Failed to archive runtime#{reset}"
      exit 1
    end
    # `ar rcs` creates and indexes the archive; a second ranlib pass is
    # redundant on both Apple and LLVM/GNU ar.
    atomic_copy(tmp_archive, runtime_archive)
  end
  t_runtime_built = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  puts "    #{green}built#{reset}  runtime #{dim}#{aligned_ms(t_runtime_built - t_runtime_start)}#{reset}"
end

# Keep the environment beside its content-addressed archive, then publish one
# atomic two-line discovery manifest. Benchmark readers can never combine the
# archive from one concurrent build with another build's flags/toolchain.
atomic_write(runtime_env_contents, runtime_env_manifest)
atomic_write([
  File.basename(runtime_archive), File.basename(runtime_env_manifest)
].join("\n") + "\n", runtime_current_manifest)

t_runtime_end = Process.clock_gettime(Process::CLOCK_MONOTONIC)

# ── Phase 1: Bootstrap compiler ───

t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

ARGV.delete("-0")
ARGV.delete("-1")
ARGV.delete("-2")
ARGV.delete("--pgo")
ARGV.delete("--force")
ARGV.delete("--no-bits")

if stage0_only && !use_spinel_bootstrap
  $stderr.puts "#{red}-0 is only available with the Spinel bootstrap#{reset}"
  exit 1
end

# ── Fingerprinting: SHA-based build caching ────────────────────

SOURCE_EXTENSIONS = %w[.rb .w .c .h .gemspec .lock].freeze
SOURCE_SKIP_DIRS = %w[.git .bundle .cache node_modules tmp].freeze

def tree_sha(*paths)
  sha = Digest::SHA256.new
  paths.each do |path|
    full = path.start_with?("/") ? path : File.join(ROOT, path)
    if File.directory?(full)
      Find.find(full) do |f|
        if File.directory?(f)
          Find.prune if SOURCE_SKIP_DIRS.include?(File.basename(f))
          next
        end
        next unless File.file?(f) && SOURCE_EXTENSIONS.include?(File.extname(f))

        sha.update(f.delete_prefix(ROOT + "/"))
        sha.update("\0")
        sha.update(file_sha(f))
        sha.update("\0")
      end
    elsif File.file?(full)
      sha.update(full.delete_prefix(ROOT + "/"))
      sha.update("\0")
      sha.update(file_sha(full))
      sha.update("\0")
    end
  end
  sha.hexdigest[0..15]
end

bit_cache_dir = File.join(build_cache_dir, "bits")
FileUtils.mkdir_p(bit_cache_dir)

def bit_build_sha(bit_path, compiler, runtime_key, link_flags, link_libs, bit_clang_opt)
  sha = Digest::SHA256.new
  sha.update(tree_sha(bit_path))
  bitfile_includes(bit_path).each do |include_path|
    sha.update(tree_sha(include_path))
  end
  sha.update(file_sha(compiler))
  sha.update(runtime_key)
  sha.update(link_flags.join("\0"))
  sha.update(link_libs.join("\0"))
  sha.update(bit_clang_opt)
  sha.hexdigest[0..15]
end

def bit_cache_stamp(bit_cache_dir, short_name)
  File.join(bit_cache_dir, "#{short_name}.sha")
end

def same_file_content?(left, right)
  return false unless File.file?(left) && File.file?(right)
  return false unless File.size(left) == File.size(right)

  system("cmp", "-s", left, right)
end

def optional_cache_complete?(path)
  File.file?(path) || File.file?("#{path}.missing")
end

def publish_optional_file(source, cached)
  marker = "#{cached}.missing"
  if File.file?(source)
    atomic_copy(source, cached)
    FileUtils.rm_f(marker)
  else
    tmp = "#{marker}.#{$$}.tmp"
    File.write(tmp, "missing\n")
    FileUtils.rm_f(cached)
    FileUtils.mv(tmp, marker)
  end
ensure
  FileUtils.rm_f(tmp) if defined?(tmp) && tmp
end

def restore_optional_file(cached, destination)
  if File.file?(cached)
    atomic_copy(cached, destination)
  else
    FileUtils.rm_f(destination)
  end
end

unless bit_only
  stage1 = File.join(build_scratch_dir, "tungsten.wc")
  stage2 = File.join(build_scratch_dir, "tungsten-self-hosted.wc")
  stage_ll_dir = File.join(build_scratch_dir, "ll")
  bootstrap_ll_tag =
    if use_spinel_bootstrap
      "spinel"
    elsif use_c_bootstrap
      "c"
    elsif pgo_build
      "pgo-ruby"
    else
      "ruby"
    end
  stage1_ll = File.join(stage_ll_dir, "stage1-#{bootstrap_ll_tag}.ll")
  stage2_ll = File.join(stage_ll_dir, "stage2-#{bootstrap_ll_tag}.ll")
  FileUtils.mkdir_p(stage_ll_dir)

  unless use_c_bootstrap
    # Legacy Ruby/Spinel paths have broader interpreter/driver dependencies.
    stage1_input_sha = tree_sha("implementations/ruby",
                                File.join(COMPILER_DIR_NAME, "tungsten.w"),
                                File.join(COMPILER_DIR_NAME, "lib"),
                                "runtime", "bin/tungsten", "bin/commands/build.rb")
    stage1_sha = Digest::SHA256.hexdigest("#{stage1_input_sha}:#{runtime_compile_key}")[0..15]
    stage1_cached = File.join(build_cache_dir, "stage1-#{stage1_sha}")
  end

  if use_c_bootstrap
    c_stage_cache_schema = "c-stage-content-v1"
    c_stage1_sources_sha = tree_sha(File.join(COMPILER_DIR_NAME, "tungsten.w"),
                                    File.join(COMPILER_DIR_NAME, "lib"))
    puts
    puts "#{bold}==> Stage 0: implementations/c VM#{reset}"
    verb, c_vm_elapsed, c_interp_for_build, c_vm_key_for_build = ensure_c_interp.call
    verb_str = verb == :cached ? "#{green}CACHED#{reset}" : "#{green}built #{reset}"
    puts "    #{verb_str} stage0 #{dim}#{aligned_ms(c_vm_elapsed)}#{reset}"

    # Optional per-invocation discovery for tooling such as the C VM
    # benchmark. Unlike a mutable `current` alias, this file belongs to the
    # requesting process and binds the exact VM/runtime/environment trio.
    requested_manifest = ENV["TUNGSTEN_BUILD_MANIFEST"].to_s
    unless requested_manifest.empty?
      requested_manifest = File.expand_path(requested_manifest, ROOT)
      FileUtils.mkdir_p(File.dirname(requested_manifest))
      atomic_write([
        "tungsten-build-manifest-v1", c_interp_for_build,
        runtime_archive, runtime_env_manifest
      ].join("\n") + "\n", requested_manifest)
    end

    puts
    puts "#{bold}==> Stage 1: implementations/c VM compiles tungsten.w#{reset}"
    stage1_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    # Fixed-point builds always use the canonical parser. The C-native parser
    # is a bootstrap.sh acceleration and intentionally emits a different
    # stage-1 IR, so an ambient environment value must not leak in here.
    lex_table_path = ENV.fetch("TUNGSTEN_LEX64_TABLE",
                               File.join(ROOT, "languages/tungsten/tungsten.lex64"))
    c_stage1_base_env = compiler_probe_env.merge(
      "TUNGSTEN_C_FAST_PARSE" => "0",
      "TUNGSTEN_CLANG_OPT" => "-O0",
      "TUNGSTEN_LEX64_TABLE" => lex_table_path
    )
    # Immutable content identity: sources, actual stage-0 binary/toolchain,
    # runtime archive identity, parser table, link flags, and probe results.
    c_stage1_identity = Digest::SHA256.hexdigest([
      c_stage1_sources_sha,
      c_stage_cache_schema,
      runtime_compile_key,
      c_vm_key_for_build,
      file_sha(c_interp_for_build),
      file_sha(lex_table_path),
      COMPILER_DIR_NAME,
      STAGE_OPT_FLAG,
      ENV["TUNGSTEN_MARCH_ARGS"].to_s,
      ambient_toolchain_identity,
      c_stage1_base_env.sort.map { |key, value| "#{key}=#{value}" }.join("\0")
    ].join("\n"))
    c_stage1_cached = File.join(build_cache_dir, "c-vm-stage1-#{c_stage1_identity}")
    c_stage1_cached_ll = "#{c_stage1_cached}.ll"
    c_stage1_cached_sidemap = "#{c_stage1_cached}.sidemap"
    if !force_build && File.executable?(c_stage1_cached) && File.file?(c_stage1_cached_ll) &&
       optional_cache_complete?(c_stage1_cached_sidemap)
      FileUtils.cp(c_stage1_cached, stage1)
      FileUtils.cp(c_stage1_cached_ll, stage1_ll)
      restore_optional_file(c_stage1_cached_sidemap, "#{stage1}.sidemap")
      t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      puts "    #{green}CACHED#{reset} stage1 #{dim}#{aligned_ms(t1 - stage1_started)} (#{c_stage1_identity[0, 16]})#{reset}"
    else
      FileUtils.rm_f(stage1_ll)
      # TUNGSTEN_CLANG_OPT=-O0 for the stage 1 link: stage 1's binary is
      # throwaway (only used to produce stage 2), and benchmarking showed
      # -O0 saves ~2s on the link with negligible cost to the stage 2
      # compiler run.
      stage1_env = c_stage1_base_env.merge(
        "TUNGSTEN_LL_DIR" => stage_ll_dir,
        "TUNGSTEN_LL_PATH" => stage1_ll
      )
      stage1_log = File.join(Dir.tmpdir, "tungsten-c-stage1.log")
      # --runtime points clang at the pre-built runtime archive (cached up
      # in the runtime stage); without it the compiler script falls into
      # link_binary's `runtime_objs == nil` branch and recompiles every
      # runtime .c file from source, costing ~1s per stage. --no-lto
      # disables full LTO at link — mixing -flto with the runtime archive's
      # thin-LTO bitcode crashes clang's linker (LLVM ERROR: Unexistent
      # dir). Spinel's stage 2 invocation uses the same combination.
      unless system(stage1_env, c_interp_for_build, TUNGSTEN_W, "compile", TUNGSTEN_W, "--out", stage1, STAGE_OPT_FLAG,
                    "--runtime", runtime_archive, "--no-lto",
                    [:out, :err] => stage1_log)
        $stderr.puts File.read(stage1_log) if File.exist?(stage1_log)
        $stderr.puts "#{red}Stage 1 (C VM) failed#{reset}"
        exit 1
      end
      if RUBY_PLATFORM =~ /darwin/ &&
         !system("codesign", "--force", "-s", "-", stage1, out: File::NULL, err: File::NULL)
        $stderr.puts "#{red}codesign failed for C VM stage 1#{reset}"
        exit 1
      end
      atomic_copy(stage1, c_stage1_cached)
      atomic_copy(stage1_ll, c_stage1_cached_ll) if File.exist?(stage1_ll)
      publish_optional_file("#{stage1}.sidemap", c_stage1_cached_sidemap)
      t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      puts "    #{green}built #{reset} stage1 #{dim}#{aligned_ms(t1 - stage1_started)}#{reset}"
    end

    if stage1_only
      install_compiler.call(stage1, "C VM stage 1 only")
      t2 = t1
    else
      puts
      puts "#{bold}==> Stage 2: Stage-1 binary compiles tungsten.w#{reset}"
      stage2_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      c_stage2_base_env = compiler_probe_env.merge(
        "TUNGSTEN_CLANG_OPT" => bootstrap_compiler_clang_opt,
        "TUNGSTEN_LEX64_TABLE" => lex_table_path
      )
      c_stage2_identity = Digest::SHA256.hexdigest([
        c_stage1_identity,
        file_sha(stage1),
        c_stage1_sources_sha,
        c_stage_cache_schema,
        runtime_compile_key,
        STAGE_OPT_FLAG,
        ENV["TUNGSTEN_MARCH_ARGS"].to_s,
        ambient_toolchain_identity,
        c_stage2_base_env.sort.map { |key, value| "#{key}=#{value}" }.join("\0")
      ].join("\n"))
      c_stage2_cached = File.join(build_cache_dir, "c-vm-stage2-#{c_stage2_identity}")
      c_stage2_cached_ll = "#{c_stage2_cached}.ll"
      c_stage2_cached_sidemap = "#{c_stage2_cached}.sidemap"
      if !force_build && File.executable?(c_stage2_cached) && File.file?(c_stage2_cached_ll) &&
         optional_cache_complete?(c_stage2_cached_sidemap)
        FileUtils.cp(c_stage2_cached, stage2)
        FileUtils.cp(c_stage2_cached_ll, stage2_ll)
        restore_optional_file(c_stage2_cached_sidemap, "#{stage2}.sidemap")
        t2 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        puts "    #{green}CACHED#{reset} stage2 #{dim}#{aligned_ms(t2 - stage2_started)} (#{c_stage2_identity[0, 16]})#{reset}"
      else
        FileUtils.rm_f(stage2_ll)
        stage2_env = c_stage2_base_env.merge(
          "TUNGSTEN_LL_DIR" => stage_ll_dir,
          "TUNGSTEN_LL_PATH" => stage2_ll
        )
        stage2_log = File.join(Dir.tmpdir, "tungsten-c-stage2.log")
        # Same --runtime + --no-lto combination as stage 1; the produced
        # stage 2 binary is the installed compiler, but bit builds use it
        # to invoke clang independently with their own LTO settings.
        unless system(stage2_env, stage1, "compile", TUNGSTEN_W, "--out", stage2, STAGE_OPT_FLAG,
                      "--runtime", runtime_archive, "--no-lto",
                      [:out, :err] => stage2_log)
          $stderr.puts File.read(stage2_log) if File.exist?(stage2_log)
          $stderr.puts "#{red}Stage 2 failed#{reset} (#{$?.inspect})"
          exit 1
        end
        t2 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        if !File.exist?(stage2)
          $stderr.puts "#{red}Stage 2 produced no output#{reset} #{dim}(#{stage2})#{reset}"
          $stderr.puts "    #{dim}stage 1 binary at #{stage1} ran cleanly but didn't write the output file —#{reset}"
          $stderr.puts "    #{dim}likely emit_ir or link_binary in compiler/tungsten.w bottomed out under the#{reset}"
          $stderr.puts "    #{dim}C VM. Check #{stage2_log} for clang/runtime errors.#{reset}"
          exit 1
        end
        atomic_copy(stage2, c_stage2_cached)
        atomic_copy(stage2_ll, c_stage2_cached_ll) if File.exist?(stage2_ll)
        publish_optional_file("#{stage2}.sidemap", c_stage2_cached_sidemap)
        puts "    #{green}built #{reset} stage2 #{dim}#{aligned_ms(t2 - stage2_started)}#{reset}"
      end

      puts
      verify_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      verified = same_file_content?(stage1_ll, stage2_ll)
      verify_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - verify_started
      if verified
        puts "    #{green}VERIFIED#{reset} #{dim}stage 1 .ll == stage 2 .ll (#{ms(verify_elapsed)})#{reset}"
      else
        # Match the ruby path: warn and ship stage 2 anyway. Exiting here
        # would leave the user with no installed compiler when an
        # unrelated divergence (e.g. metadata jitter) triggers a false
        # negative.
        $stderr.puts "    #{red}WARNING#{reset} stage 1 and stage 2 .ll differ!"
        if File.exist?(stage1_ll) && File.exist?(stage2_ll)
          $stderr.puts "    #{dim}stage 1 .ll: #{file_sha(stage1_ll)[0..15]}#{reset}"
          $stderr.puts "    #{dim}stage 2 .ll: #{file_sha(stage2_ll)[0..15]}#{reset}"
        else
          $stderr.puts "    #{dim}missing emitted .ll for one or both stages#{reset}"
        end
      end

      puts
      install_compiler.call(stage2, "C VM")
    end
  elsif use_spinel_bootstrap
    stage1 = File.join(build_scratch_dir, "tungsten-stage1")
    stage2 = File.join(build_scratch_dir, "tungsten-stage2")
    spinel_dir = File.join(ROOT, "implementations/spinel")
    spinel_build_dir = File.join(spinel_dir, "build")
    spinel_bootstrap = File.join(spinel_dir, "bin/bootstrap")
    spinel_build_stage0 = File.join(spinel_dir, "bin/build_stage0")
    spinel_runtime = File.join(spinel_build_dir, "runtime-stage0.a")
    spinel_stage0_log = File.join(spinel_build_dir, "build_stage0.log")
    spinel_stage0_status = File.join(spinel_build_dir, "tungsten-stage0.status")
    spinel_stage1_ll = File.join(spinel_build_dir, "stage1-spinel.ll")
    spinel_stage2_ll = File.join(spinel_build_dir, "stage2-spinel.ll")
    spinel_stage2_ll_dir = File.join(spinel_build_dir, "stage2-ll")
    spinel_stage2_status = File.join(spinel_build_dir, "tungsten-stage2.status")
    spinel_env = {}
    spinel_env["TUNGSTEN_CLANG_OPT"] = "-O1" if ENV["TUNGSTEN_CLANG_OPT"].to_s.empty?
    spinel_env["SP_GC_DISABLE"] = ENV.fetch("SP_GC_DISABLE", "1")
    spinel_env["TUNGSTEN_SPINEL_FORCE_STAGE0"] = "1" if force_build

    if stage0_only
      puts
      puts "#{bold}==> Compiler: Spinel stage 0#{reset}"
      stage0_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      unless system(spinel_env, spinel_build_stage0, [:out, :err] => spinel_stage0_log)
        warn File.read(spinel_stage0_log) if File.exist?(spinel_stage0_log)
        $stderr.puts "#{red}Spinel stage0 preparation failed#{reset}"
        exit 1
      end
      t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      t2 = t1
      stage0_status = File.exist?(spinel_stage0_status) ? File.read(spinel_stage0_status).strip : "built"
      if stage0_status == "cached"
        puts "    #{green}CACHED#{reset} stage0 #{dim}#{aligned_ms(t1 - stage0_started)}#{reset}"
      else
        puts "    #{green}built#{reset}  stage0 #{dim}#{aligned_ms(t1 - stage0_started)}#{reset}"
      end
    elsif stage2_only
      puts
      puts "#{bold}==> Stage 2: Spinel stage-1 binary compiles tungsten.w#{reset}"
      unless File.executable?(stage1)
        $stderr.puts "#{red}No Spinel stage-1 binary at #{stage1} — run full build first#{reset}"
        exit 1
      end
      unless system(spinel_env, spinel_build_stage0, out: File::NULL)
        $stderr.puts "#{red}Spinel stage0 preparation failed#{reset}"
        exit 1
      end
      FileUtils.mkdir_p(spinel_stage2_ll_dir)
      tmp_ll = File.join(spinel_stage2_ll_dir, "tungsten.ll")
      FileUtils.rm_f(tmp_ll)
      stage2_env = spinel_env.merge(
        "TUNGSTEN_LL_DIR" => spinel_stage2_ll_dir,
        "TUNGSTEN_LL_PATH" => tmp_ll
      )
      unless system(
        stage2_env, stage1, "compile", "compiler/tungsten.w", "--runtime", spinel_runtime, "--no-lto",
        STAGE_OPT_FLAG, "--out", stage2
      )
        $stderr.puts "#{red}Stage 2 failed#{reset} (#{$?.inspect})"
        exit 1
      end
      FileUtils.cp(tmp_ll, spinel_stage2_ll) if File.exist?(tmp_ll)
      File.write(spinel_stage2_status, "built\n")
    else
      puts
      label = stage1_only ? "Spinel bootstrap (stage 1 only)" : "Spinel bootstrap"
      puts "#{bold}==> Compiler: #{label}#{reset}"
      env = spinel_env.merge("TUNGSTEN_SPINEL_STAGE2" => stage2)
      env["TUNGSTEN_SPINEL_FORCE_STAGE2"] = "1" if force_build
      env["TUNGSTEN_SPINEL_STAGE1_ONLY"] = "1" if stage1_only
      unless system(env, spinel_bootstrap)
        $stderr.puts "#{red}Spinel bootstrap failed#{reset}"
        exit 1
      end
    end

    unless stage0_only
      FileUtils.cp(spinel_stage1_ll, stage1_ll) if File.exist?(spinel_stage1_ll)
      FileUtils.cp(spinel_stage2_ll, stage2_ll) if File.exist?(spinel_stage2_ll)
      t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      t2 = t1
    end

    unless stage0_only
      if stage1_only
        install_compiler.call(stage1, "Spinel stage 1 only")
      else
        puts
        puts "#{bold}==> Verify: stage 1 .ll == stage 2 .ll#{reset}"
        verify_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        verified = same_file_content?(stage1_ll, stage2_ll)
        verify_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - verify_started
        if verified
          puts "    #{green}VERIFIED#{reset} #{dim}stage 1 .ll == stage 2 .ll (#{ms(verify_elapsed)})#{reset}"
        else
          $stderr.puts "    #{red}ERROR#{reset} stage 1 and stage 2 .ll differ!"
          if File.exist?(stage1_ll) && File.exist?(stage2_ll)
            s1_hash = file_sha(stage1_ll)
            s2_hash = file_sha(stage2_ll)
            $stderr.puts "    #{dim}stage 1 .ll: #{s1_hash[0..15]}#{reset}"
            $stderr.puts "    #{dim}stage 2 .ll: #{s2_hash[0..15]}#{reset}"
          else
            $stderr.puts "    #{dim}missing emitted .ll for one or both stages#{reset}"
          end
          exit 1
        end

        t2 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        stage2_status = File.exist?(spinel_stage2_status) ? File.read(spinel_stage2_status).strip : "built"
        puts if stage2_status == "built"
        install_compiler.call(stage2, stage2_only ? "Spinel stage 2" : "Spinel", announce: stage2_status == "built")
      end
    end
  else
  unless stage2_only
    if !force_build && File.executable?(stage1_cached)
      FileUtils.cp(stage1_cached, stage1)
      puts
      puts "#{bold}==> Stage 1: cached#{reset} #{dim}(#{stage1_sha})#{reset}"
      t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    else
      if File.executable?(CUSTOM_RUBY)
        ruby_label = "custom Ruby"
        custom_gem_dir = File.join(ROOT, "build/ruby/lib/ruby/gems/4.0.0")
        stage1_env = compiler_toolchain_env.merge(
          "GEM_HOME" => custom_gem_dir,
          "GEM_PATH" => custom_gem_dir,
          "TUNGSTEN_LL_DIR" => stage_ll_dir,
          "TUNGSTEN_LL_PATH" => stage1_ll
        )
        stage1_cmd = [
          stage1_env, CUSTOM_RUBY, GEM_EXE, TUNGSTEN_W, "--", "compile", "-v", TUNGSTEN_W, "--out", stage1,
          STAGE_OPT_FLAG
        ]
      else
        ruby_label = "system Ruby"
        stage1_env = compiler_toolchain_env.merge("TUNGSTEN_LL_DIR" => stage_ll_dir, "TUNGSTEN_LL_PATH" => stage1_ll)
        stage1_cmd = [
          stage1_env, GEM_EXE, TUNGSTEN_W, "--", "compile", "-v", TUNGSTEN_W, "--out", stage1, STAGE_OPT_FLAG
        ]
      end
      puts
      puts "#{bold}==> Stage 1: #{ruby_label} compiles tungsten.w#{reset}"
      FileUtils.rm_f(stage1_ll)
      unless system(*stage1_cmd)
        $stderr.puts "#{red}Stage 1 failed#{reset}"
        exit 1
      end
      # Re-sign: macOS Sequoia SIGKILLs freshly-built binaries
      if RUBY_PLATFORM =~ /darwin/ &&
         !system("codesign", "--force", "-s", "-", stage1, out: File::NULL, err: File::NULL)
        $stderr.puts "#{red}codesign failed for stage 1#{reset}"
        exit 1
      end
      atomic_copy(stage1, stage1_cached)
      t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      puts "    #{dim}Stage 1: #{aligned_ms(t1 - t0)}#{reset}"
    end
  else
    t1 = t0
    unless File.exist?(stage1)
      $stderr.puts "#{red}No stage-1 binary at #{stage1} — run full build first#{reset}"
      exit 1
    end
    puts "#{bold}==> Skipping Stage 1#{reset} #{dim}(reusing #{stage1})#{reset}"
  end

  if stage1_only
    install_compiler.call(stage1, "stage 1 only")
    t2 = t1
  else
    stage2_input_sha = tree_sha(File.join(COMPILER_DIR_NAME, "tungsten.w"),
                                File.join(COMPILER_DIR_NAME, "lib"),
                                "runtime", "bin/tungsten", "bin/commands/build.rb")
    stage2_sha = Digest::SHA256.hexdigest("#{stage1_sha}:#{stage2_input_sha}:#{bootstrap_compiler_clang_opt}")[0..15]
    stage2_cached = File.join(build_cache_dir, "stage2-#{stage2_sha}")

    if !force_build && File.executable?(stage2_cached)
      FileUtils.cp(stage2_cached, stage2)
      puts
      puts "#{bold}==> Stage 2: cached#{reset} #{dim}(#{stage2_sha})#{reset}"
      t2 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    else
      puts
      puts "#{bold}==> Stage 2: Stage-1 binary compiles tungsten.w#{reset}"
      FileUtils.rm_f(stage2_ll)
      stage2_env = compiler_toolchain_env.merge(
        "TUNGSTEN_LL_DIR" => stage_ll_dir,
        "TUNGSTEN_LL_PATH" => stage2_ll,
        "TUNGSTEN_CLANG_OPT" => bootstrap_compiler_clang_opt
      )
      unless system(stage2_env, stage1, "compile", "-v", TUNGSTEN_W, "--out", stage2, STAGE_OPT_FLAG)
        $stderr.puts "#{red}Stage 2 failed#{reset} (#{$?.inspect})"
        exit 1
      end
      FileUtils.cp(stage2, stage2_cached)
      t2 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      puts "    #{dim}Stage 2: #{aligned_ms(t2 - t1)}#{reset}"
    end
    puts

    # Verify: compare emitted LLVM IR, not final Mach-O metadata.
    verify_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    verified = same_file_content?(stage1_ll, stage2_ll)
    verify_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - verify_started
    if verified
      puts "    #{green}VERIFIED#{reset} #{dim}stage 1 .ll == stage 2 .ll (#{ms(verify_elapsed)})#{reset}"
    else
      $stderr.puts "    #{red}WARNING#{reset} stage 1 and stage 2 .ll differ!"
      if File.exist?(stage1_ll) && File.exist?(stage2_ll)
        s1_hash = file_sha(stage1_ll)
        s2_hash = file_sha(stage2_ll)
        $stderr.puts "    #{dim}stage 1 .ll: #{s1_hash[0..15]}#{reset}"
        $stderr.puts "    #{dim}stage 2 .ll: #{s2_hash[0..15]}#{reset}"
      else
        $stderr.puts "    #{dim}missing emitted .ll for one or both stages#{reset}"
      end
    end

    if pgo_build
      puts
      puts "#{bold}==> PGO: profile-guided optimization#{reset}"
      t_pgo_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      pgo_dir = File.join(build_scratch_dir, "pgo")
      pgo_profraw = File.join(pgo_dir, "default.profraw")
      pgo_profdata = File.join(pgo_dir, "default.profdata")
      pgo_instrumented = File.join(pgo_dir, "tungsten-instrumented")
      pgo_optimized = File.join(pgo_dir, "tungsten-pgo")
      FileUtils.mkdir_p(pgo_dir)

      # 3a: Recompile stage-2 IR with profiling instrumentation
      puts "    #{dim}instrumenting...#{reset}"
      pgo_ll = stage2_ll.dup
      unless File.exist?(pgo_ll)
        $stderr.puts "#{red}No stage-2 .ll at #{pgo_ll} — cannot PGO#{reset}"
        exit 1
      end
      pgo_instr_flags = %w[-O3 -DNDEBUG -march=native -mtune=native -fprofile-generate -mllvm -vp-counters-per-site=8]
      pgo_instr_flags += RUBY_PLATFORM =~ /darwin/ ? %w[-Wl,-dead_strip -Wl,-stack_size,0x8000000] : %w[-fuse-ld=lld -Wl,--gc-sections]
      pgo_instr_flags += onig_cflags + onig_libs
      pgo_srcs = runtime_srcs.map { |s| File.join(RUNTIME_DIR, s) }
      # Check if the compiler IR uses zstd
      if File.read(pgo_ll).include?("@w_slab_init_static_zstd(") || File.read(pgo_ll).include?("@w_zstd_compress_llvm_escaped(")
        pgo_srcs << File.join(RUNTIME_DIR, "slab_zstd.c")
        zstd_cf = `pkg-config --cflags libzstd 2>/dev/null`.split
        zstd_lf = `pkg-config --libs libzstd 2>/dev/null`.split
        pgo_instr_flags += zstd_cf + zstd_lf
      end
      unless system(runtime_cc, *pgo_instr_flags, pgo_ll, *pgo_srcs, "-o", pgo_instrumented)
        $stderr.puts "#{red}PGO instrumentation build failed#{reset}"
        exit 1
      end

      # 3b: Run instrumented binary on representative workload (compile itself)
      puts "    #{dim}profiling...#{reset}"
      ENV["LLVM_PROFILE_FILE"] = pgo_profraw
      unless system(pgo_instrumented, "compile", TUNGSTEN_W, "--out", "/dev/null")
        $stderr.puts "#{red}PGO profiling run failed#{reset}"
        exit 1
      end
      ENV.delete("LLVM_PROFILE_FILE")

      # 3c: Merge profile data
      llvm_profdata = `xcrun -f llvm-profdata 2>/dev/null`.strip
      llvm_profdata = "llvm-profdata" if llvm_profdata.empty?
      unless system(llvm_profdata, "merge", "-sparse", pgo_profraw, "-o", pgo_profdata)
        $stderr.puts "#{red}llvm-profdata merge failed#{reset}"
        exit 1
      end

      # 3d: Rebuild with profile data
      puts "    #{dim}optimizing...#{reset}"
      pgo_opt_flags = %w[-O3 -DNDEBUG -march=native -mtune=native -flto] + ["-fprofile-use=#{pgo_profdata}"]
      pgo_opt_flags += RUBY_PLATFORM =~ /darwin/ ? %w[-Wl,-dead_strip -Wl,-stack_size,0x8000000] : %w[-fuse-ld=lld -Wl,--gc-sections]
      pgo_opt_flags += onig_cflags + onig_libs
      pgo_opt_flags += zstd_cf + zstd_lf if defined?(zstd_cf) && zstd_cf
      unless system(runtime_cc, *pgo_opt_flags, pgo_ll, *pgo_srcs, "-o", pgo_optimized)
        $stderr.puts "#{red}PGO optimization build failed#{reset}"
        exit 1
      end

      t_pgo_end = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      puts "    #{dim}PGO: #{ms(t_pgo_end - t_pgo_start)}#{reset}"

      puts
      install_compiler.call(pgo_optimized, "PGO")
    else
      puts
      install_compiler.call(stage2)
    end
  end
  end
end

# ── Phase 2: Runtime archive already built above ─────────────────
t3 = t_runtime_start
t4 = t_runtime_end

# ── Shared link config ──────────────────────────────────────────

bit_clang_opt = ENV["TUNGSTEN_BITS_CLANG_OPT"].to_s
bit_clang_opt = "-O0" if bit_clang_opt.empty?
link_flags = %W[#{bit_clang_opt} -DNDEBUG -march=native -mtune=native #{LTO_FLAG}]
if RUBY_PLATFORM =~ /darwin/
  link_flags << "-Wl,-dead_strip"
else
  # Linux (validated on Ubuntu 24.04): GNU ld can't read the LTO-bitcode
  # objects in runtime.a — link with lld. -dead_strip is ld64-only; the GNU
  # equivalent is --gc-sections.
  link_flags += %w[-fuse-ld=lld -Wl,--gc-sections]
end
link_libs = []
link_libs += ["-L#{openssl_prefix}/lib", "-lssl", "-lcrypto"] if tls_flags.any?
link_libs += ["-L#{nghttp2_prefix}/lib", "-lnghttp2"] if http2_flags.any?
link_libs += onig_libs
runtime_key = Digest::SHA256.hexdigest([
  runtime_dependency_files.map { |path| file_sha(path) }.join(":"),
  cc_flags.join("\0"),
  runtime_cc,
  runtime_ar,
  runtime_ranlib,
  link_flags.join("\0"),
  link_libs.join("\0")
].join("\n"))

colors = [bold, dim, green, red, reset]

# ── Phase 3: Build bits ─────────────────────────────────────────

puts ""
t5 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
bits_built = 0
bits_skipped = 0

if skip_bits
  puts "#{bold}==> Bits: skipped#{reset}"
elsif bit_only
  # Build just the current bit
  short_name = File.basename(bit_root).sub(/^tungsten-/, "")
  entry = File.join(bit_root, "lib", "#{short_name}.w")
  bin_dir = File.join(bit_root, "bin")
  FileUtils.mkdir_p(bin_dir)
  out_bin = File.join(bin_dir, short_name)
  bit_sha = bit_build_sha(bit_root, COMPILER_BIN, runtime_key, link_flags, link_libs, bit_clang_opt)
  stamp = bit_cache_stamp(bit_cache_dir, short_name)

  puts "#{bold}==> Building #{File.basename(bit_root)}#{reset}"
  if !force_build && File.executable?(out_bin) && File.exist?(stamp) && File.read(stamp).strip == bit_sha
    puts "    #{dim}skip#{reset}    #{project_relative_path(out_bin)}"
    bits_skipped = 1
  elsif compile_bit(entry, out_bin, COMPILER_BIN, GEM_EXE, TUNGSTEN_W, runtime_archive, link_flags, link_libs,
                    bit_clang_opt, compiler_toolchain_env, colors)
    File.write(stamp, "#{bit_sha}\n")
    bits_built = 1
  else
    exit 1
  end
else
  # Build all bits with bin/ directories
  puts "#{bold}==> Bits: compiling entry points#{reset}"
  bit_dir = File.join(ROOT, "bits")

  Dir[File.join(bit_dir, "*/")].sort.each do |bit_path|
    bin_dir = File.join(bit_path, "bin")
    next unless File.directory?(bin_dir)

    bit_name = File.basename(bit_path)
    short_name = bit_name.sub(/^tungsten-/, "")

    entry = File.join(bit_path, "lib", "#{short_name}.w")
    next unless File.exist?(entry)

    out_bin = File.join(bin_dir, short_name)
    bit_sha = bit_build_sha(bit_path, COMPILER_BIN, runtime_key, link_flags, link_libs, bit_clang_opt)
    stamp = bit_cache_stamp(bit_cache_dir, short_name)
    if !force_build && File.executable?(out_bin) && File.exist?(stamp) && File.read(stamp).strip == bit_sha
      puts "    #{dim}skip#{reset}    #{project_relative_path(out_bin)}"
      bits_skipped += 1
    elsif compile_bit(entry, out_bin, COMPILER_BIN, GEM_EXE, TUNGSTEN_W, runtime_archive, link_flags, link_libs,
                      bit_clang_opt, compiler_toolchain_env, colors)
      File.write(stamp, "#{bit_sha}\n")
      bits_built += 1
    else
      bits_skipped += 1
    end
  end
end

t6 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

# ── Summary ──────────────────────────────────────────────────────

puts ""
total = t6 - t0
if bit_only
  puts "#{bold}==> Done#{reset} #{dim}(runtime #{ms(t4 - t3)}, compile #{ms(t6 - t5)})#{reset}"
else
  bits_summary = skip_bits ? "skipped" : "#{bits_built} built"
  bits_summary += ", #{bits_skipped} skipped" if bits_skipped > 0
  t2 ||= t0
  puts "#{bold}==> Done#{reset} #{dim}(compiler #{ms(t2 - t0)}, runtime #{ms(t4 - t3)}, bits: #{bits_summary} #{ms(t6 - t5)})#{reset}"
end
puts
