require "optparse"
require "tmpdir"
require "stringio"
require "net/http"
require "fileutils"

# ── Compile infrastructure (mirrors compile.rb) ──────────────────

PRINT_IR    = File.join(ROOT, "compiler/print_ir.w")
RUNTIME_C   = File.join(ROOT, "runtime/runtime.c")
RUNTIME_DIR = File.join(ROOT, "runtime")
EVENT_SRCS  = Dir[File.join(RUNTIME_DIR, "event_*.c")]
TLS_C       = File.join(RUNTIME_DIR, "tls.c")
TLS_STUB_C  = File.join(RUNTIME_DIR, "tls_stub.c")
LINUX       = RUBY_PLATFORM =~ /linux/

require File.join(ROOT, "implementations/ruby/lib/tungsten/build_flags")
# Forge builds a local dev app server (never a distributed artifact), so it is
# always host-tuned; sourced from BuildFlags so no raw -march lives here.
FORGE_MARCH = Tungsten::BuildFlags.march(:native)
FORGE_CLANG_FLAGS = if LINUX
                      ["-O2", "-DNDEBUG", *FORGE_MARCH, "-lm"]
                    else
                      ["-O2", "-DNDEBUG", *FORGE_MARCH, "-Wl,-dead_strip", "-Wl,-stack_size,0x4000000"]
                    end

def find_header(*paths)
  paths.each { |p| return File.dirname(File.dirname(File.dirname(p))) if File.exist?(p) }
  nil
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

HTTP2_ENABLED = ENV["HTTP2"] || ENV["TUNGSTEN_HTTP2"]
NGHTTP2_PREFIX = if HTTP2_ENABLED
                   find_header(
                     "/usr/include/nghttp2/nghttp2.h",
                     "/opt/homebrew/opt/libnghttp2/include/nghttp2/nghttp2.h",
                   )
                 end
HTTP2_C = HTTP2_ENABLED && NGHTTP2_PREFIX ? File.join(RUNTIME_DIR, "http2.c") : nil
HTTP2_FLAGS = if HTTP2_ENABLED && NGHTTP2_PREFIX
                f = ["-DTUNGSTEN_HTTP2"]
                f += ["-I#{NGHTTP2_PREFIX}/include", "-L#{NGHTTP2_PREFIX}/lib"] unless NGHTTP2_PREFIX == "/usr"
                f + ["-lnghttp2"]
              else
                []
              end

AKS_C    = File.join(RUNTIME_DIR, "aks.c")
SSMR_C   = File.join(RUNTIME_DIR, "ssmr_witness.c")
HAMMER_C = File.join(RUNTIME_DIR, "hammer.c")
FORGE_EXTRA_SRCS  = [TLS_STUB_C, (TLS_ENABLED && OPENSSL_PREFIX ? TLS_C : nil), HTTP2_C, (File.exist?(SSMR_C) ? SSMR_C : nil), (File.exist?(AKS_C) ? AKS_C : nil), (File.exist?(HAMMER_C) ? HAMMER_C : nil)].compact
FORGE_EXTRA_FLAGS = TLS_FLAGS + HTTP2_FLAGS

# ── Defaults ─────────────────────────────────────────────────────

DEFAULT_PORT = 7474
PID_DIR      = File.join(Dir.home, ".tungsten")
PID_FILE     = File.join(PID_DIR, "forge.pid")

COMPILER      = File.join(ROOT, "bin/tungsten-compiler") unless defined?(COMPILER)
HAVE_COMPILER = File.executable?(COMPILER) unless defined?(HAVE_COMPILER)

# ANSI
BOLD  = "\e[1m"
DIM   = "\e[2m"
CYAN  = "\e[36m"
GREEN = "\e[32m"
YELLOW = "\e[33m"
RED   = "\e[91m"
RESET = "\e[0m"

# ── Helpers ──────────────────────────────────────────────────────

def default_source(port, workers)
  <<~W
    listener = Socket.listen("0.0.0.0", #{port}, 128)
    listener.serve_http(#{workers}) { |req|
      Response.new(200, "Hello, World!\\n")
    }
  W
end

def compile_forge_app(source_path, output_path)
  if HAVE_COMPILER
    system(COMPILER, "compile", source_path, "--out", output_path, out: File::NULL, err: File::NULL)
  else
    $LOAD_PATH.unshift(File.join(ROOT, "implementations/ruby/lib"))
    require "tungsten"
    old_argv = ARGV.dup
    ARGV.replace([source_path])
    emit_source = File.read(PRINT_IR)
    old_stdout = $stdout
    $stdout = StringIO.new
    begin
      Tungsten::Interpreter.new.run(emit_source, file_path: PRINT_IR)
      ir = $stdout.string
    ensure
      $stdout = old_stdout
      ARGV.replace(old_argv)
    end

    ll_file = output_path + ".ll"
    File.write(ll_file, ir)
    ok = system("clang", *FORGE_CLANG_FLAGS, *FORGE_EXTRA_FLAGS, "-Wno-override-module",
                RUNTIME_C, *EVENT_SRCS, *FORGE_EXTRA_SRCS, ll_file, "-o", output_path,
                err: File::NULL)
    File.delete(ll_file) if File.exist?(ll_file)
    ok
  end
end

def probe_server(port)
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  http = Net::HTTP.new("127.0.0.1", port)
  http.open_timeout = 1
  http.read_timeout = 1
  http.get("/")
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
  elapsed
rescue
  nil
end

def wait_for_server(port, timeout: 10)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
  loop do
    return true if probe_server(port)
    return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    sleep 0.1
  end
end

def read_pid
  return nil unless File.exist?(PID_FILE)
  pid = File.read(PID_FILE).strip.to_i
  return nil if pid <= 0
  Process.kill(0, pid) # check if alive
  pid
rescue Errno::ESRCH, Errno::EPERM
  File.delete(PID_FILE)
  nil
end

def write_pid(pid)
  FileUtils.mkdir_p(PID_DIR)
  File.write(PID_FILE, pid.to_s)
end

def format_ms(seconds)
  if seconds < 0.001
    "%.0fus" % (seconds * 1_000_000)
  elsif seconds < 1
    "%.1fms" % (seconds * 1000)
  else
    "%.2fs" % seconds
  end
end

# ── Subcommands ──────────────────────────────────────────────────

def forge_env(max_mode, capacity_headers)
  env = {}
  env["TUNGSTEN_FORGE_MAX"] = "1" if max_mode
  env["TUNGSTEN_FORGE_CAPACITY"] = "1" if capacity_headers && !max_mode
  env
end

def forge_run(source_file, port, workers, max_mode, capacity_headers)
  Dir.mktmpdir("tungsten-forge") do |dir|
    src_path = source_file
    unless src_path
      src_path = File.join(dir, "app.w")
      File.write(src_path, default_source(port, workers))
    end

    bin_path = File.join(dir, "forge")
    $stderr.print "#{DIM}Compiling...#{RESET}"
    unless compile_forge_app(src_path, bin_path)
      $stderr.puts "\r#{RED}Compile failed#{RESET}     "
      exit 1
    end
    $stderr.puts "\r#{GREEN}Compiled#{RESET}           "

    pid = spawn(forge_env(max_mode, capacity_headers), bin_path)
    unless wait_for_server(port)
      $stderr.puts "#{RED}Server failed to start on port #{port}#{RESET}"
      Process.kill("TERM", pid) rescue nil
      Process.wait(pid) rescue nil
      exit 1
    end

    $stderr.puts "#{BOLD}#{CYAN}forge#{RESET} #{DIM}listening on#{RESET} #{BOLD}http://127.0.0.1:#{port}/#{RESET}"
    $stderr.puts "#{DIM}Ctrl+C to stop#{RESET}\n\n"

    total = 0
    latencies = []
    interval_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    trap("INT") do
      $stderr.puts "\n#{DIM}Shutting down...#{RESET}"
      Process.kill("TERM", pid) rescue nil
      exit 0
    end

    loop do
      sleep 5

      # Probe the server
      5.times do
        lat = probe_server(port)
        if lat
          total += 1
          latencies << lat
        end
      end

      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      elapsed = now - interval_start

      if latencies.any?
        rps = (total.to_f / elapsed).round(1)
        min_lat = format_ms(latencies.min)
        max_lat = format_ms(latencies.max)
        $stderr.print "\r#{DIM}reqs:#{RESET} #{BOLD}#{total}#{RESET}  #{DIM}rps:#{RESET} #{rps}  #{DIM}min:#{RESET} #{GREEN}#{min_lat}#{RESET}  #{DIM}max:#{RESET} #{YELLOW}#{max_lat}#{RESET}    "
      else
        $stderr.print "\r#{RED}server not responding#{RESET}    "
      end
    end
  rescue Errno::ECHILD
    # Server process exited
  end
end

def forge_start(source_file, port, workers, max_mode, capacity_headers)
  existing = read_pid
  if existing
    $stderr.puts "#{YELLOW}Forge already running#{RESET} (pid #{existing})"
    exit 1
  end

  Dir.mktmpdir("tungsten-forge") do |dir|
    src_path = source_file
    unless src_path
      src_path = File.join(dir, "app.w")
      File.write(src_path, default_source(port, workers))
    end

    # Compile to a persistent location so tmpdir can be cleaned up
    forge_dir = File.join(Dir.home, ".tungsten", "forge")
    FileUtils.mkdir_p(forge_dir)
    bin_path = File.join(forge_dir, "server")

    $stderr.print "#{DIM}Compiling...#{RESET}"
    unless compile_forge_app(src_path, bin_path)
      $stderr.puts "\r#{RED}Compile failed#{RESET}     "
      exit 1
    end
    $stderr.puts "\r#{GREEN}Compiled#{RESET}           "

    pid = spawn(forge_env(max_mode, capacity_headers), bin_path, [:out, :err] => File::NULL)
    Process.detach(pid)
    write_pid(pid)

    unless wait_for_server(port)
      $stderr.puts "#{RED}Server failed to start on port #{port}#{RESET}"
      Process.kill("TERM", pid) rescue nil
      File.delete(PID_FILE) if File.exist?(PID_FILE)
      exit 1
    end

    $stderr.puts "#{BOLD}#{CYAN}forge#{RESET} #{DIM}started on#{RESET} #{BOLD}http://127.0.0.1:#{port}/#{RESET} #{DIM}(pid #{pid})#{RESET}"
  end
end

def forge_stop
  pid = read_pid
  unless pid
    $stderr.puts "#{DIM}No forge server running#{RESET}"
    exit 0
  end

  Process.kill("TERM", pid)
  File.delete(PID_FILE) if File.exist?(PID_FILE)
  $stderr.puts "#{DIM}Stopped forge server#{RESET} (pid #{pid})"
rescue Errno::ESRCH
  File.delete(PID_FILE) if File.exist?(PID_FILE)
  $stderr.puts "#{DIM}Process already stopped#{RESET}"
end

# ── CLI ──────────────────────────────────────────────────────────

port = DEFAULT_PORT
subcommand = nil
source_file = nil
workers = 4
max_mode = false
capacity_headers = false

args = ARGV.dup
ARGV.clear

# Parse subcommand
case args.first
when "start" then subcommand = :start; args.shift
when "stop"  then subcommand = :stop;  args.shift
end

parser = OptionParser.new do |opts|
  opts.banner = "Usage: tungsten forge [start|stop] [FILE] [--port PORT]"
  opts.on("-p", "--port PORT", Integer, "Port (default: #{DEFAULT_PORT})") { |p| port = p }
  opts.on("-w", "--workers N", Integer, "Worker threads for generated app (default: 4)") { |w| workers = w }
  opts.on("--capacity", "Send X-Forge-G/X-Forge-QD capacity headers") { capacity_headers = true }
  opts.on("--max", "Max throughput mode") { max_mode = true }
  opts.on("-h", "--help", "Show this help") { puts opts; exit 0 }
end
rest = parser.parse(args)
source_file = rest.first

if source_file && !File.exist?(source_file)
  $stderr.puts "#{RED}File not found:#{RESET} #{source_file}"
  exit 1
end

case subcommand
when :start then forge_start(source_file, port, workers, max_mode, capacity_headers)
when :stop  then forge_stop
else             forge_run(source_file, port, workers, max_mode, capacity_headers)
end
