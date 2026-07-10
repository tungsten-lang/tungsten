require "open3"

PRINT_IR    = File.join(ROOT, "compiler/print_ir.w")
PRINT_AST   = File.join(ROOT, "compiler/print_ast.w")
EMIT_IR     = File.join(ROOT, "compiler/print_ir.w")
RUNTIME_C   = File.join(ROOT, "runtime/runtime.c")
RUNTIME_DIR = File.join(ROOT, "runtime")
SLAB_ZSTD_C = File.join(RUNTIME_DIR, "slab_zstd.c")
TLS_C       = File.join(RUNTIME_DIR, "tls.c")
TLS_STUB_C  = File.join(RUNTIME_DIR, "tls_stub.c")
LINUX = RUBY_PLATFORM =~ /linux/
MACOS = RUBY_PLATFORM =~ /darwin/
# Phase 6: thin-LTO by default, full-LTO via --release. The runtime
# archive is built with the matching LTO mode by build.rb so the linker
# has bitcode for both halves and can cross-optimize through dispatch
# (w_method_call_cached etc.).
RELEASE_MODE = ARGV.include?("--release")
ARGV.delete("--release") if RELEASE_MODE
# LTO policy: the compiled `compile` backend links a fast native-object runtime
# archive by default and does whole-program LTO only for --release/--native/--lto.
# Strip those here (OptionParser would reject --lto) and forward them verbatim to
# the fast path so `tungsten -o file.w --release` reaches the backend's LTO path.
LTO_MODE = ARGV.delete("--lto") ? true : false
NATIVE_MODE = ARGV.delete("--native") ? true : false
LTO_FORWARD = []
LTO_FORWARD << "--release" if RELEASE_MODE
LTO_FORWARD << "--lto" if LTO_MODE
LTO_FORWARD << "--native" if NATIVE_MODE
LTO_FLAG = RELEASE_MODE ? "-flto=full" : "-flto=thin"

# Floating-point math mode. Unlike --release (which only tunes Ruby-side LTO),
# these are codegen-level and must reach the compiled backend, so they are
# stripped here (OptionParser would reject them) and forwarded verbatim to the
# `tungsten-compiler compile` invocation below. Default mode is :precise.
# The bash wrapper turns --fast-math into `--fast` (plus a FAST_MATH define).
MATH_MODE_FLAGS = []
if ARGV.include?("--strict-math")
  MATH_MODE_FLAGS << "--strict-math"
  ARGV.delete("--strict-math")
end
if ARGV.include?("--fast") || ARGV.include?("-fast")
  MATH_MODE_FLAGS << "--fast"
  ARGV.delete("--fast")
  ARGV.delete("-fast")
end
# Cross-compilation: --target <triple> [--sysroot <path>] retarget codegen + the
# link (compiler/tungsten.w + target.w). Value-taking, so strip each flag AND its
# argument and forward both verbatim to `tungsten-compiler compile`. A runnable
# cross-binary also needs --sysroot pointing at the target's libc/crt/system libs.
if (ti = ARGV.index("--target")) && ARGV[ti + 1]
  MATH_MODE_FLAGS << "--target" << ARGV[ti + 1]
  ARGV.delete_at(ti + 1)
  ARGV.delete_at(ti)
end
if (si = ARGV.index("--sysroot")) && ARGV[si + 1]
  MATH_MODE_FLAGS << "--sysroot" << ARGV[si + 1]
  ARGV.delete_at(si + 1)
  ARGV.delete_at(si)
end
require File.join(ROOT, "implementations/ruby/lib/tungsten/build_flags")
MARCH_FLAGS = Tungsten::BuildFlags.march(RELEASE_MODE ? :portable : :native)
CLANG_FLAGS = if ENV["CLANG_FLAGS"]
                ENV["CLANG_FLAGS"].split
              elsif LINUX
                ["-O3", "-DNDEBUG", *MARCH_FLAGS, LTO_FLAG, "-lm"]
              else
                ["-O3", "-DNDEBUG", *MARCH_FLAGS, LTO_FLAG, "-Wl,-dead_strip"]
              end

# Helper: find a header in standard paths
def find_header(*paths)
  # Returns the install prefix (e.g. /opt/homebrew/opt/openssl@3)
  # from a header path like prefix/include/openssl/ssl.h (3 levels up)
  paths.each { |p| return File.dirname(File.dirname(File.dirname(p))) if File.exist?(p) }
  nil
end

def zstd_flags
  cflags = `pkg-config --cflags libzstd 2>/dev/null`.split
  libs = `pkg-config --libs libzstd 2>/dev/null`.split

  if cflags.empty? && File.exist?("/opt/homebrew/include/zstd.h")
    cflags = ["-I/opt/homebrew/include"]
  end

  if libs.empty?
    if File.exist?("/opt/homebrew/lib/libzstd.dylib") || File.exist?("/opt/homebrew/lib/libzstd.a")
      libs = ["-L/opt/homebrew/lib", "-lzstd"]
    else
      libs = ["-lzstd"]
    end
  end

  [cflags, libs]
end

def onig_flags
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

def ir_needs_zstd_runtime?(ir)
  ir.include?("@w_slab_init_static_zstd(") || ir.include?("@w_zstd_compress_llvm_escaped(")
end

TLS_ENABLED = ENV["TLS"] || ENV["TUNGSTEN_TLS"]
OPENSSL_PREFIX = if TLS_ENABLED
                   find_header(
                     "/usr/include/openssl/ssl.h",
                     "#{`brew --prefix openssl@3 2>/dev/null`.strip}/include/openssl/ssl.h",
                     "/opt/homebrew/opt/openssl@3/include/openssl/ssl.h",
                   )
                 end
TLS_FLAGS = if TLS_ENABLED && OPENSSL_PREFIX
              f = ["-DTUNGSTEN_TLS"]
              f += ["-I#{OPENSSL_PREFIX}/include", "-L#{OPENSSL_PREFIX}/lib"] unless OPENSSL_PREFIX == "/usr"
              f + ["-lssl", "-lcrypto"]
            else
              []
            end

# HTTP/2 support (opt-in via HTTP2=1)
HTTP2_ENABLED = ENV["HTTP2"] || ENV["TUNGSTEN_HTTP2"]
NGHTTP2_PREFIX = if HTTP2_ENABLED
                   find_header(
                     "/usr/include/nghttp2/nghttp2.h",
                     "/opt/homebrew/opt/libnghttp2/include/nghttp2/nghttp2.h",
                   )
                 end
if HTTP2_ENABLED && NGHTTP2_PREFIX
  HTTP2_C = File.join(RUNTIME_DIR, "http2.c")
  HTTP2_FLAGS = begin
    f = ["-DTUNGSTEN_HTTP2"]
    f += ["-I#{NGHTTP2_PREFIX}/include", "-L#{NGHTTP2_PREFIX}/lib"] unless NGHTTP2_PREFIX == "/usr"
    f + ["-lnghttp2"]
  end
else
  HTTP2_C     = nil
  HTTP2_FLAGS = []
end

# HTTP/3 support (opt-in via HTTP3=1)
HTTP3_ENABLED = ENV["HTTP3"] || ENV["TUNGSTEN_HTTP3"]
NGTCP2_PREFIX = if HTTP3_ENABLED
                  find_header(
                    "/usr/include/ngtcp2/ngtcp2.h",
                    "/opt/homebrew/opt/libngtcp2/include/ngtcp2/ngtcp2.h",
                  )
                end
NGHTTP3_PREFIX = if HTTP3_ENABLED
                   find_header(
                     "/usr/include/nghttp3/nghttp3.h",
                     "/opt/homebrew/opt/libnghttp3/include/nghttp3/nghttp3.h",
                   )
                 end
if HTTP3_ENABLED && NGTCP2_PREFIX && NGHTTP3_PREFIX
  HTTP3_C = File.join(RUNTIME_DIR, "http3.c")
  HTTP3_FLAGS = begin
    f = ["-DTUNGSTEN_HTTP3"]
    f += ["-I#{NGTCP2_PREFIX}/include", "-L#{NGTCP2_PREFIX}/lib"] unless NGTCP2_PREFIX == "/usr"
    f += ["-lngtcp2", "-lngtcp2_crypto_ossl"]
    f += ["-I#{NGHTTP3_PREFIX}/include", "-L#{NGHTTP3_PREFIX}/lib"] unless NGHTTP3_PREFIX == "/usr"
    f + ["-lnghttp3"]
  end
else
  HTTP3_C     = nil
  HTTP3_FLAGS = []
end

# io_uring support (Linux only, opt-in via USE_IOURING=1 env var)
# Disabled by default: io_uring POLL_ADD is slower than epoll for readiness polling.
# Will be enabled when kTLS (Phase 2) makes completion I/O worthwhile.
URING_FLAGS = if LINUX && ENV["USE_IOURING"] && find_header("/usr/include/liburing.h", "/usr/include/liburing/io_uring.h")
                ["-DUSE_IOURING", "-luring"]
              else
                []
              end

EVENT_SRCS = if MACOS
               [File.join(RUNTIME_DIR, "event_kqueue.c")]
             elsif LINUX && URING_FLAGS.any?
               [File.join(RUNTIME_DIR, "event_iouring.c")]
             elsif LINUX
               [File.join(RUNTIME_DIR, "event_epoll.c")]
             else
               Dir[File.join(RUNTIME_DIR, "event_*.c")].sort
             end

AKS_C       = File.join(RUNTIME_DIR, "aks.c")
SSMR_C      = File.join(RUNTIME_DIR, "ssmr_witness.c")
HAMMER_C    = File.join(RUNTIME_DIR, "hammer.c")
METAL_M     = File.join(RUNTIME_DIR, "metal.m")
# hid_bridge.m: USB-HID (Elgato Stream Deck + dials) for the REPL scrub loop.
# Needed in the compiled compiler binary because repl.w calls w_hid_streamdeck_*.
HID_M       = File.join(RUNTIME_DIR, "hid_bridge.m")
METAL_FRAMEWORK_FLAGS = MACOS ? ["-framework", "Metal", "-framework", "Foundation", "-framework", "IOKit", "-framework", "CoreFoundation"] : []
ACCELERATE_FRAMEWORK_FLAGS = MACOS ? ["-framework", "Accelerate"] : []
EXTRA_SRCS  = [(TLS_ENABLED && OPENSSL_PREFIX ? TLS_C : TLS_STUB_C), HTTP2_C, HTTP3_C, (File.exist?(AKS_C) ? AKS_C : nil), (File.exist?(HAMMER_C) ? HAMMER_C : nil)].compact
LEXCHAR_TABLES_C = File.join(RUNTIME_DIR, "lexchar_tables.c")
EXTRA_FLAGS = TLS_FLAGS + HTTP2_FLAGS + HTTP3_FLAGS + URING_FLAGS
BLAS_BRIDGE_C = File.join(RUNTIME_DIR, "blas_bridge.c")
# The Apple GPU/HID bridges (and their frameworks, mostly via ObjC
# autolinking) are linked ONLY when the program's IR references a bridge
# symbol; otherwise runtime.c's W_NO_APPLE_BRIDGES stubs stand in and the
# binary skips Metal/Foundation/IOKit/AppKit entirely (~2ms warm and far
# cheaper first-run dyld closure).
BRIDGE_SRCS = [(MACOS && File.exist?(METAL_M) ? METAL_M : nil), (MACOS && File.exist?(HID_M) ? HID_M : nil)].compact
def ir_needs_apple_bridges?(ir)
  MACOS && ir.match?(/@"?w_(metal|hid|gpu|gfx)_/)
end
def ir_needs_blas?(ir)
  MACOS && ir.match?(/@"?w_blas_/)
end
# Data-table gating (weak twins in runtime.c make absence safe): the 512KB
# SSMR prime-witness table and the 348KB SIMD-lexer tables link only when the
# IR mentions prime / lexchars respectively.
def ir_needs_ssmr?(ir)
  ir.include?("prime")
end
def ir_needs_lexchars?(ir)
  ir.include?("lchs") || ir.include?("lexchars")
end

flag_ast       = false
flag_check     = false
flag_interpret = false
flag_lex       = false
flag_ll        = false
flag_verbose   = false
out_path       = nil
eval_code      = nil

interactive    = false
intern_algo    = "raw"
extra_c_includes = ENV.fetch("TUNGSTEN_C_INCLUDES", "").split(File::PATH_SEPARATOR).reject(&:empty?)
extra_link_flags = ENV.fetch("TUNGSTEN_LINK_FLAGS", "").split(/\s+/).reject(&:empty?)
extra_clang_flags = ENV.fetch("TUNGSTEN_CLANG_FLAGS", "").split(/\s+/).reject(&:empty?)

parser = OptionParser.new do |opts|
  opts.banner = <<~BANNER
    Usage: tungsten [command] [flags] [file] [--] [arguments]

    Commands:
      compile FILE   Compile a .w file to a native binary (-o FILE)
      run FILE       Interpret a .w file
      repl           Interactive REPL (alias: console)
      start          First-run welcome: what Tungsten is + your next step
      new NAME       Scaffold a new project
      build          Bootstrap the self-hosted compiler
      doctor         Check your toolchain
      fmt FILE       Format .w source
      bit ...        The Bit package manager
      ai / symbolicate / forge / flame

    Flags:
  BANNER

  opts.on "-e", "--eval CODE", "Evaluate expression" do |code|
    eval_code = code
  end

  opts.on "-c", "--check", "Check syntax and exit" do
    flag_check = true
  end

  opts.on "--ast", "--parse", "Print the AST" do
    flag_ast = true
  end

  opts.on "--lex", "Print tokens" do
    flag_lex = true
  end

  opts.on "--ll", "Print LLVM IR (for .w files)" do
    flag_ll = true
  end

  opts.on "--ruby", "Use Ruby interpreter (skip compilation)" do
    flag_interpret = true
  end

  opts.on "-i", "--interactive", "Start REPL after evaluating -e" do
    interactive = true
  end

  opts.on "-o", "--out FILE", "Write compiled binary to FILE (for .w files)" do |f|
    out_path = f
  end

  opts.on "--intern ALGO", %w[raw zstd], "Static slab encoding (raw or zstd)" do |algo|
    intern_algo = algo
  end

  opts.on "-v", "Print version, enable verbose mode" do
    flag_verbose = true
    $LOAD_PATH.unshift(File.join(ROOT, "implementations/ruby/lib"))
    require "tungsten/version"
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    require "tungsten"
    ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round
    ruby_label = Tungsten::Runtime::Builtins.runtime_version_label
    if $stderr.tty? && !ENV["NO_COLOR"]
      $stderr.puts "\e[1m\e[33m✶ Tungsten\e[0m \e[1m#{Tungsten::VERSION}\e[0m \e[2m·\e[0m \e[2mloads in\e[0m \e[36m#{ms}ms\e[0m \e[2m·\e[0m \e[36m#{ruby_label}\e[0m"
    else
      $stderr.puts "tungsten #{Tungsten::VERSION} (#{ruby_label})"
    end
  end

  opts.on "--explain CODE", "Explain an error code (e.g. E_PARSE_UNEXPECTED_TOKEN)" do |code|
    code = code.strip.upcase
    registry = File.join(ROOT, "doc/explain.md")
    sections = File.exist?(registry) ? File.read(registry).split(/^## /)[1..] || [] : []
    section = sections.find { |s| s.lines.first&.strip == code }
    if section
      body = section.lines[1..].join.strip
      puts "#{code}\n\n#{body}"
    else
      puts "No lesson for #{code} yet — the registry lives in doc/explain.md."
      puts "Known codes with lessons: #{sections.map { |s| s.lines.first&.strip }.compact.join(", ")}"
    end
    exit 0
  end

  opts.on "--version", "Print version and exit" do
    $LOAD_PATH.unshift(File.join(ROOT, "implementations/ruby/lib"))
    require "tungsten/version"
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    require "tungsten"
    ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round
    ruby_label = Tungsten::Runtime::Builtins.runtime_version_label
    if $stdout.tty? && !ENV["NO_COLOR"]
      puts "\e[1m\e[33m✶ Tungsten\e[0m \e[1m#{Tungsten::VERSION}\e[0m \e[2m·\e[0m \e[2mloads in\e[0m \e[36m#{ms}ms\e[0m \e[2m·\e[0m \e[36m#{ruby_label}\e[0m"
    else
      puts "tungsten #{Tungsten::VERSION} (#{ruby_label})"
    end
    exit 0
  end

  opts.on "--copyright", "Print copyright and exit" do
    puts "tungsten - Copyright (c) 2013–2026 Erik Peterson"
    exit 0
  end

  opts.on "--clear-cache", "Clear all .memo cache files" do
    cache_dir = File.join(Dir.home, ".tungsten", "cache")
    files = Dir.glob(File.join(cache_dir, "*.memo"))
    files.each { |f| File.delete(f) }
    puts "Cleared #{files.size} cache file#{"s" unless files.size == 1}"
    exit 0
  end

  opts.on "--dump-cache FILE", "Dump a .memo cache file" do |f|
    path = if File.exist?(f)
             f
           else
             File.join(Dir.home, ".tungsten", "cache", "#{f}.memo")
           end
    unless File.exist?(path)
      $stderr.puts "Cache file not found: #{path}"
      exit 1
    end
    raw = File.binread(path)
    if raw[0, 4] == "WMEM"
      # Binary format (compiler)
      version = raw[4, 4].unpack1("V")
      arity = raw[8, 4].unpack1("V")
      count = raw[12, 4].unpack1("V")
      puts "Cache: #{File.basename(path, '.memo')} (binary format v#{version})"
      puts "Arity: #{arity}"
      puts "Entries: #{count}"
      puts
      entry_size = (arity + 1) * 16  # each WValue is 16 bytes (tag:i64 + data:i64)
      count.times do |i|
        offset = 16 + i * entry_size
        args = arity.times.map do |j|
          arg_offset = offset + j * 16
          tag, data = raw[arg_offset, 16].unpack("q<q<")
          case tag
          when 0 then data
          when 1 then data != 0
          when 2 then nil
          else "<tag=#{tag} data=#{data}>"
          end
        end
        result_offset = offset + arity * 16
        rtag, rdata = raw[result_offset, 16].unpack("q<q<")
        result = case rtag
                 when 0 then rdata
                 when 1 then rdata != 0
                 when 2 then nil
                 else "<tag=#{rtag} data=#{rdata}>"
                 end
        puts "  #{args.inspect} => #{result.inspect}"
      end
    else
      # Marshal format (interpreter)
      data = Marshal.load(raw)
      puts "Cache: #{File.basename(path, '.memo')}"
      puts "Entries: #{data.size}"
      puts
      data.each do |args, result|
        puts "  #{args.inspect} => #{result.inspect}"
      end
    end
    exit 0
  end

  opts.on "-h", "--help", "Display this help message" do
    puts opts
    exit 0
  end
end

rest = parser.parse(ARGV)

begin

# -v with no other action: exit after printing version
if flag_verbose && !eval_code && !interactive && rest.empty?
  exit 0
end

# -e: evaluate expression
if eval_code
  # --ruby (flag_interpret) means "use the Ruby interpreter, skip compilation".
  # Honor it here just like the file path does (see `if flag_interpret` below);
  # without this guard `--ruby -e` silently execs the native compiler instead.
  if HAVE_COMPILER && !flag_interpret && !flag_check && !flag_lex && !flag_ast && !interactive
    exec COMPILER, "run", "-e", eval_code
  end
  load_gem!
  if flag_check
    Tungsten::Parser.parse(eval_code)
    puts "200 OK"
  elsif flag_lex
    lexer = Tungsten::Lexer.new(eval_code)
    types = []
    while (tok = lexer.next_token)
      s = tok.type.to_s
      s += "[#{tok.value}]" if tok.value
      types << s
      break if tok.type == :EOF
    end
    puts "\n    #{types.join(" ")}\n\n"
  elsif flag_ast
    ast = Tungsten::Parser.parse(eval_code)
    puts ast.inspect
  else
    if HAVE_COMPILER && !flag_interpret
      system COMPILER, "run", "-e", eval_code, *rest
    else
      Tungsten::Interpreter.new(argv: rest).run(eval_code)
    end
  end
  if interactive
    load_gem! unless defined?(Tungsten)
    Tungsten::REPL.new.start
  end
  exit 0
end

# -i: interactive mode after -e (REPL playground is `wit` / `tungsten console`)
if interactive
  load_gem!
  Tungsten::REPL.new.start
  exit 0
end

script = rest.first

unless script
  puts parser
  exit 1
end

# A bare word with no extension and no path separator is more likely a mistyped
# command than a file. Suggest the closest command when it is within 2 edits and
# the winner is unambiguous (a tie at the same distance suggests nothing).
# Self-contained on purpose: this path must work on a fresh clone where the gem's
# dependencies aren't installed, so it can't reuse Units.levenshtein (same
# algorithm + threshold as implementations/ruby/lib/tungsten/support/units.rb).
CLI_COMMANDS = %w[compile compile-batch run repl console start new build doctor
                  fmt bit ai symbolicate forge flame fire].freeze

def levenshtein_distance(a, b)
  return b.length if a.empty?
  return a.length if b.empty?
  prev = (0..b.length).to_a
  curr = Array.new(b.length + 1)
  (1..a.length).each do |i|
    curr[0] = i
    (1..b.length).each do |j|
      cost = a[i - 1] == b[j - 1] ? 0 : 1
      curr[j] = [curr[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost].min
    end
    prev, curr = curr, prev
  end
  prev[b.length]
end

def suggest_command(word)
  return nil if word.nil? || word.empty? || word.include?("/") || !File.extname(word).empty?
  best = nil
  best_dist = 3 # threshold 2: anything >= 3 is "not close"
  tied = false
  CLI_COMMANDS.each do |cand|
    next if (cand.length - word.length).abs > 2
    d = levenshtein_distance(word, cand)
    if d < best_dist
      best = cand
      best_dist = d
      tied = false
    elsif d == best_dist
      tied = true
    end
  end
  (best_dist <= 2 && !tied) ? best : nil
end

unless File.exist?(script)
  $stderr.puts "File not found: #{script}"
  if (suggestion = suggest_command(script))
    $stderr.puts "Did you mean: tungsten #{suggestion}"
  end
  exit 1
end

ext = File.extname(script)
args = rest[1..]

# Auto-link a bit's Bitfile `includes` (extra C sources) when the file being
# compiled lives inside a bit directory. Mirrors `bin/tungsten build`'s
# bitfile_includes so a bit that `use`s another bit's C runtime (e.g.
# tungsten-json's json_simd.c) links via plain `tungsten -o` without the caller
# setting TUNGSTEN_C_INCLUDES. Files outside a bit, or in a bit whose Bitfile
# declares no `includes`, are unaffected.
def find_bit_root(dir)
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
  incs = []
  text.scan(/\binclude\s+["']([^"']+)["']/) { |m| incs << File.expand_path(m.first, bit_root) }
  text.scan(/\bincludes\s+\[(.*?)\]/m) do |m|
    m.first.scan(/["']([^"']+)["']/) { |p| incs << File.expand_path(p.first, bit_root) }
  end
  incs.uniq
end

if script && File.exist?(script)
  _bit_root = find_bit_root(File.dirname(File.expand_path(script)))
  _bit_incs = _bit_root ? bitfile_includes(_bit_root) : []
  unless _bit_incs.empty?
    # The `-o` fast path execs the compiled compiler, which reads C includes
    # from the TUNGSTEN_C_INCLUDES env (not compile.rb's clang_sources). Set
    # both: the env for the fast path, extra_c_includes for the slow / --ll path.
    _existing = ENV.fetch("TUNGSTEN_C_INCLUDES", "").split(File::PATH_SEPARATOR).reject(&:empty?)
    ENV["TUNGSTEN_C_INCLUDES"] = (_existing + _bit_incs).uniq.join(File::PATH_SEPARATOR)
    extra_c_includes = (extra_c_includes + _bit_incs).uniq
  end
end

# --check, --lex, --ast for files (use Ruby interpreter)
if flag_check && (ext != ".w" || true)
  load_gem!
  source = File.read(script)
  Tungsten::Parser.parse(source)
  puts "200 OK"
  exit 0
end

if flag_lex
  load_gem!
  source = File.read(script)
  lexer = Tungsten::Lexer.new(source)
  types = []
  while (tok = lexer.next_token)
    types << tok.type.to_s
    break if tok.type == :EOF
  end
  puts types.join(" ")
  exit 0
end

case ext
when ".w"
  if flag_interpret
    load_gem!
    source = File.read(script)
    Tungsten::Interpreter.new(argv: args).run(source, file_path: script)
    exit 0
  elsif flag_ast
    load_gem!
    source = File.read(PRINT_AST)
    Tungsten::Interpreter.new(argv: [script] + args).run(source, file_path: PRINT_AST)
    exit 0
  elsif flag_ll
    if HAVE_COMPILER
      Dir.mktmpdir("tungsten-ll") do |dir|
        staged_bin = File.join(dir, File.basename(script, ".w"))
        staged_ll = File.join("/tmp/tungsten", File.basename(script, ".w") + ".ll")
        File.delete(staged_ll) if File.exist?(staged_ll)
        cmd = [COMPILER, "compile", script, "--out", staged_bin, "--intern", intern_algo] + MATH_MODE_FLAGS
        out, err, status = Open3.capture3(*cmd)
        unless status.success? && File.exist?(staged_ll)
          # Surface the compiler's real diagnostic from whichever stream it used.
          # capture3 splits stdout/stderr, and the error formatter writes to
          # stdout when not attached to a TTY — so prefer stderr, fall back to
          # stdout, and only emit the generic line if the compiler said nothing.
          diag = err.strip.empty? ? out : err
          $stderr.puts(diag.strip.empty? ? "failed to emit LLVM IR" : diag)
          exit 1
        end
        print File.read(staged_ll)
      end
      exit 0
    end

    if intern_algo != "raw"
      $stderr.puts "--intern #{intern_algo} requires the compiled compiler"
      exit 1
    end

    load_gem!
    source = File.read(PRINT_IR)
    Tungsten::Interpreter.new(argv: [script] + args).run(source, file_path: PRINT_IR)
    exit 0
  elsif HAVE_COMPILER && !out_path
    load_gem!
    source = File.read(script)
    Tungsten::Interpreter.new(argv: args).run(source, file_path: script)
    exit 0
  elsif HAVE_COMPILER
    # Fast path: delegate to compiled binary
    cmd = [COMPILER]
    if out_path
      cmd += ["compile", script, "--out", out_path, "--intern", intern_algo] + MATH_MODE_FLAGS + LTO_FORWARD
    else
      cmd += ["run", script, *args]
    end
    exec(*cmd)
  else
    if intern_algo != "raw"
      $stderr.puts "--intern #{intern_algo} requires the compiled compiler"
      exit 1
    end

    # Slow path: emit IR via Ruby interpreter, then clang
    load_gem!
    require "stringio"
    emit_source = File.read(EMIT_IR)
    old_stdout = $stdout
    $stdout = StringIO.new
    begin
      Tungsten::Interpreter.new(argv: [script]).run(emit_source, file_path: EMIT_IR)
      ir = $stdout.string
    ensure
      $stdout = old_stdout
    end

    onig_cflags, onig_libs = onig_flags
    clang_flags = CLANG_FLAGS + EXTRA_FLAGS + onig_cflags + ["-I#{RUNTIME_DIR}"] + extra_clang_flags
    clang_sources = [RUNTIME_C, *EVENT_SRCS, *EXTRA_SRCS, *extra_c_includes]
    if ir_needs_apple_bridges?(ir)
      clang_flags += METAL_FRAMEWORK_FLAGS
      clang_sources += BRIDGE_SRCS
    end
    if ir_needs_blas?(ir)
      clang_flags += ACCELERATE_FRAMEWORK_FLAGS
      clang_sources << BLAS_BRIDGE_C
    end
    clang_sources << SSMR_C if ir_needs_ssmr?(ir) && File.exist?(SSMR_C)
    clang_sources << LEXCHAR_TABLES_C if ir_needs_lexchars?(ir) && File.exist?(LEXCHAR_TABLES_C)
    # (no else: runtime.c's weak bridge stubs stand in when the .m files are
    # not linked — same mechanism as the fast path in compiler/tungsten.w)
    link_flags = onig_libs + extra_link_flags
    if ir_needs_zstd_runtime?(ir)
      zstd_cflags, zstd_libs = zstd_flags
      clang_flags += zstd_cflags + zstd_libs
      clang_sources << SLAB_ZSTD_C
    end

    if out_path
      if flag_ll
        # Write .ll alongside the binary for inspection
        ll_path = File.join(File.dirname(out_path), File.basename(out_path, ".*") + ".ll")
        File.write(ll_path, ir)
      end
      # Pipe IR to clang via stdin
      IO.popen(["clang", "-x", "ir", "-", "-x", "none", *clang_flags, *clang_sources, *link_flags, "-o", out_path], "w") do |pipe|
        pipe.write(ir)
      end
      unless $?.success?
        $stderr.puts "clang failed"
        exit 1
      end
      $stderr.puts "Built #{out_path}"
    else
      # Compile to temp binary and run immediately
      Dir.mktmpdir("tungsten") do |dir|
        bin_file = File.join(dir, "out")
        IO.popen(["clang", "-x", "ir", "-", "-x", "none", *clang_flags, *clang_sources, *link_flags, "-o", bin_file], "w") do |pipe|
          pipe.write(ir)
        end
        unless $?.success?
          $stderr.puts "clang failed"
          exit 1
        end
        exec bin_file, *args
      end
    end
  end

else
  # Fall back to Ruby interpreter for unknown extensions
  load_gem!
  source = File.read(script)
  if flag_ast
    ast = Tungsten::Parser.parse(source)
    puts ast.inspect
  else
    Tungsten::Interpreter.new(argv: args).run(source, file_path: script)
  end
end

rescue SystemExit
  raise
rescue => e
  if defined?(Tungsten::ErrorReporter) && e.is_a?(Tungsten::Error)
    reporter = Tungsten::ErrorReporter.new(color: $stderr.tty? && !ENV["NO_COLOR"])
    $stderr.puts reporter.format(e)
  else
    color = $stderr.tty? && !ENV["NO_COLOR"]
    label = color ? "\e[91merror:\e[0m \e[97m#{e.class}: #{e.message}\e[0m" : "error: #{e.class}: #{e.message}"
    $stderr.puts label
    prefix = "#{ROOT}/"
    e.backtrace.first(15).each { |line| $stderr.puts "  #{line.delete_prefix(prefix)}" }
  end
  exit 1
end
