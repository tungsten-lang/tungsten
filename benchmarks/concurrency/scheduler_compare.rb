#!/usr/bin/env ruby
# Build exactly the same public-API harness against two runtime checkouts,
# then run isolated ABBA samples. Never treats failed/timeout cells as timing.
require "json"
require "optparse"
require "open3"
require "timeout"
require "tmpdir"
require "fileutils"
require "digest"

options = { pairs: 5, timeout: 20.0, build_timeout: 180.0, cells: [], mp: false }
parser = OptionParser.new do |p|
  p.banner = "Usage: ruby scheduler_compare.rb --baseline RUNTIME --candidate RUNTIME [options]"
  p.on("--baseline DIR") { |v| options[:baseline] = File.expand_path(v) }
  p.on("--candidate DIR") { |v| options[:candidate] = File.expand_path(v) }
  p.on("--build-dir DIR") { |v| options[:build_dir] = File.expand_path(v) }
  p.on("--output FILE") { |v| options[:output] = File.expand_path(v) }
  p.on("--pairs N", Integer, "ABBA blocks per cell (default 5)") { |v| options[:pairs] = v }
  p.on("--timeout SECONDS", Float, "Per-cell limit (default 20)") { |v| options[:timeout] = v }
  p.on("--build-timeout SECONDS", Float) { |v| options[:build_timeout] = v }
  p.on("--cell MODE:TASKS:ROUNDS:WORKERS", "Repeatable; replaces defaults") { |v| options[:cells] << v }
  p.on("--mp", "Add optional MP stress; unsafe baselines may fail") { options[:mp] = true }
  p.on("--skip-build", "Use existing baseline/candidate binaries in build-dir") { options[:skip_build] = true }
  p.on("--build-only", "Compile and report binary paths without timing") { options[:build_only] = true }
end
parser.parse!
abort(parser.to_s) unless options[:baseline] && options[:candidate] && ARGV.empty?
abort("pairs/timeouts must be positive") unless options[:pairs] > 0 && options[:timeout] > 0 && options[:build_timeout] > 0
abort("--skip-build requires --build-dir") if options[:skip_build] && !options[:build_dir]
%i[baseline candidate].each do |lane|
  abort("missing runtime.c in #{options[lane]}") unless File.file?(File.join(options[lane], "runtime.c"))
end
options[:build_dir] ||= Dir.mktmpdir("tungsten-scheduler-compare.")
FileUtils.mkdir_p(options[:build_dir])
options[:output] ||= File.join(options[:build_dir], "samples.jsonl")
abort("refusing to overwrite #{options[:output]}") if File.exist?(options[:output])

def bounded_run(command, seconds)
  stdout, stderr, status, timed_out = "", "", nil, false
  Open3.popen3(*command, pgroup: true) do |stdin, out, err, waiter|
    stdin.close
    readers = [Thread.new { out.read }, Thread.new { err.read }]
    begin
      Timeout.timeout(seconds) { status = waiter.value }
    rescue Timeout::Error
      timed_out = true
      begin
        Process.kill("KILL", -waiter.pid)
      rescue Errno::ESRCH
      end
      status = waiter.value
    ensure
      stdout, stderr = readers.map(&:value)
    end
  end
  { command: command, timeout: timed_out, exit: status.exitstatus,
    signal: status.termsig, stdout: stdout, stderr: stderr }
end

source = File.join(__dir__, "scheduler_public.c")
makefile = File.join(__dir__, "scheduler_public.mk")
executables = {}
any_failed = false
File.open(options[:output], "w") do |log|
  log.sync = true
  metadata = { kind: "metadata", timestamp: Time.now.utc.to_s, options: options,
               harness_sha256: Digest::SHA256.file(source).hexdigest, runtimes: {} }
  %i[baseline candidate].each do |lane|
    runtime = options[lane]
    git = bounded_run(["git", "-C", runtime, "rev-parse", "HEAD"], 10)
    dirty = bounded_run(["git", "-C", runtime, "status", "--porcelain", "--", "."], 10)
    files = %w[runtime.c runtime.h event_loop.h event_kqueue.c event_epoll.c event_iouring.c Makefile]
    metadata[:runtimes][lane] = { directory: runtime, commit: git[:stdout].strip,
      dirty: dirty[:stdout], sha256: files.to_h { |f| [f, Digest::SHA256.file(File.join(runtime, f)).hexdigest] } }
    executables[lane] = File.join(options[:build_dir], "scheduler-#{lane}")
  end
  log.puts(JSON.generate(metadata))
  %i[baseline candidate].each do |lane|
    unless options[:skip_build]
      command = ["make", "-C", options[lane], "-f", "Makefile", "-f", makefile,
                 "RUNTIME_DIR=#{options[lane]}/", "SCHED_BENCH_SOURCE=#{source}",
                 "SCHED_BENCH_OUTPUT=#{executables[lane]}", "scheduler-bench-exe"]
      warn("Building #{lane}: #{executables[lane]}")
      result = bounded_run(command, options[:build_timeout])
      log.puts(JSON.generate(result.merge(kind: "build", lane: lane)))
      abort("#{lane} build failed; see #{options[:output]}") if result[:timeout] || result[:exit] != 0
    end
    abort("missing executable: #{executables[lane]}") unless File.executable?(executables[lane])
    log.puts(JSON.generate(kind: "executable", lane: lane,
      path: executables[lane], sha256: Digest::SHA256.file(executables[lane]).hexdigest))
  end
  if options[:build_only]
    puts(JSON.pretty_generate(executables.merge(log: options[:output])))
    exit 0
  end
  cells = options[:cells]
  cells = %w[coop:1:1000000:1 coop:64:16384:1 sharded:128:8192:4 ready:64:1024:1 ready-park:64:128:1 deadline:64:32:1] if cells.empty?
  cells += ["mp:64:16384:4"] if options[:mp]
  cells.each do |cell|
    parts = cell.split(":")
    abort("invalid cell: #{cell}") unless parts.size == 4 && %w[coop mp sharded ready ready-park deadline].include?(parts[0]) && parts.drop(1).all? { |x| x.match?(/\A[1-9][0-9]*\z/) }
    samples = { baseline: [], candidate: [] }
    blocks = Hash.new { |h, k| h[k] = { baseline: [], candidate: [] } }
    failed = false
    # One warmup in each lane is logged, checked, and excluded from timings.
    schedule = [[:baseline, -1], [:candidate, -1]]
    options[:pairs].times { |block| %i[baseline candidate candidate baseline].each { |lane| schedule << [lane, block] } }
    schedule.each_with_index do |(lane, block), position|
      result = bounded_run([executables[lane], *parts], options[:timeout])
      row = result.merge(kind: block == -1 ? "warmup" : "sample", lane: lane,
                         cell: cell, block: block, position: position)
      begin
        raise "timeout/exit failure" if result[:timeout] || result[:exit] != 0
        payload = JSON.parse(result[:stdout])
        expected_count = parts[1].to_i * parts[2].to_i
        expected_sum = if %w[ready ready-park].include?(parts[0])
          parts[1].to_i * (0...parts[2].to_i).sum { |i| 1 + (i & 127) }
        else
          n, r = parts[1].to_i, parts[2].to_i
          n * r * (r - 1) / 2 + r * n * (n + 1) / 2
        end
        raise "count/checksum mismatch" unless payload["completed"] == expected_count && payload["checksum"] == expected_sum && payload["expected_checksum"] == expected_sum
        if parts[0] == "sharded"
          n, r, w = parts.drop(1).map(&:to_i)
          per_worker = n / w
          expected_workers = (0...w).map do |worker|
            first = worker * per_worker
            per_worker * r * (r - 1) / 2 + r * per_worker * (2 * first + per_worker + 1) / 2
          end
          raise "per-worker checksum mismatch" unless payload["worker_checksums"] == expected_workers
        end
        raise "invalid timing" unless payload["wall_ms"].is_a?(Numeric) && payload["wall_ms"].positive?
        row[:measurement] = payload
        if block >= 0
          samples[lane] << payload["ns_per_op"]
          blocks[block][lane] << payload["ns_per_op"]
        end
      rescue StandardError => error
        row[:failure] = error.message
        failed = true
        any_failed = true
      end
      log.puts(JSON.generate(row))
      if row[:failure]
        warn("#{cell} #{lane}: FAILED (#{row[:failure]}); no comparison for this cell")
        break
      end
    end
    next if failed
    median = ->(xs) { ys = xs.sort; (ys[(ys.size - 1) / 2] + ys[ys.size / 2]) / 2.0 }
    a, b = median.call(samples[:baseline]), median.call(samples[:candidate])
    paired_ratios = blocks.values.map do |block|
      block[:candidate].sum / block[:baseline].sum
    end
    summary = { kind: "summary", cell: cell, samples_per_lane: samples[:baseline].size,
                baseline_ns: a, candidate_ns: b, candidate_over_baseline: b / a,
                abba_block_ratios: paired_ratios, median_abba_ratio: median.call(paired_ratios) }
    log.puts(JSON.generate(summary))
    puts(format("%-28s baseline=%10.3f ns candidate=%10.3f ns paired B/A=%.4f", cell, a, b, summary[:median_abba_ratio]))
  end
end
warn("Raw metadata/builds/samples: #{options[:output]}")
exit(any_failed ? 1 : 0)
