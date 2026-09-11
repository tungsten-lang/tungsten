#!/usr/bin/env ruby
# Bounded, isolated CPU-cadence comparison with the ordinary adaptive GPU fleet.
# Every run retains its command, process samples, phase records and exact best.
require "digest"
require "fileutils"
require "json"
require "open3"
require "optparse"
require "time"
require_relative "verify_tensor"

PHASE_KEYS = %w[controls_ms intake_ms leases_ms harvest_ms reseeds_ms launch_ms status_ms].freeze

def monotonic
  Process.clock_gettime(Process::CLOCK_MONOTONIC)
end

def fields(text)
  text.to_s.split.filter_map do |token|
    key, value = token.split("=", 2)
    [key, value] if value
  end.to_h
end

def cpu_seconds(value)
  days, clock = value.include?("-") ? value.split("-", 2) : ["0", value]
  parts = clock.split(":").map(&:to_f)
  parts.reverse.each_with_index.sum { |number, position| number * 60**position } + days.to_f * 86_400
end

def read_status(path)
  fields(File.read(path)) if File.file?(path)
rescue Errno::ENOENT
  nil
end

def sample_process(pid)
  output, status = Open3.capture2("/bin/ps", "-p", pid.to_s, "-o", "time=,rss=")
  values = output.split
  return {} unless status.success? && values.length == 2
  # macOS can return an exited-but-unreaped task with reset time/RSS fields.
  return {} unless Integer(values[1], 10).positive?
  { cpu_seconds: cpu_seconds(values[0]), rss_kib: Integer(values[1], 10) }
end

def sample_gpu
  output, status = Open3.capture2("/usr/sbin/ioreg", "-r", "-d", "1", "-c", "AGXAccelerator")
  match = output.match(/"Device Utilization %"\s*=\s*(\d+)/)
  status.success? && match ? match[1].to_i : nil
end

def power_source
  output, status = Open3.capture2("/usr/bin/pmset", "-g", "batt")
  status.success? ? output.lines.first.to_s.strip : "unavailable"
end

def owned_processes(root, run_tag, seen)
  output, = Open3.capture2("/bin/ps", "-axo", "pid=,ppid=,pgid=,uid=,lstart=,command=")
  processes = output.lines.filter_map do |line|
    values = line.strip.split(/\s+/, 10)
    next unless values.length == 10 && values[3].to_i == Process.uid
    { pid: values[0].to_i, ppid: values[1].to_i, pgid: values[2].to_i,
      started: values[4..8].join(" "), command: values[9] }
  end
  owned = processes.select do |process|
    identity = [process[:started], process[:command]]
    tagged = process[:command].include?(run_tag)
    (process[:pid] == root && tagged) || seen[process[:pid]] == identity ||
      (tagged && process[:command].start_with?("/tmp/metaflip_", "/private/tmp/metaflip_", "sh -c cd "))
  end
  loop do
    parents = owned.map { |process| process[:pid] }
    children = processes.select { |process| parents.include?(process[:ppid]) && !parents.include?(process[:pid]) }
    break if children.empty?
    owned.concat(children)
  end
  owned.each { |process| seen[process[:pid]] = [process[:started], process[:command]] }
  owned
end

def signal_owned(root, run_tag, seen, signal)
  # Do not signal a whole process group inferred from a child: helpers can be
  # reparented or share a group with services that do not belong to this run.
  owned_processes(root, run_tag, seen).reverse_each do |process|
    next if process[:pid] <= 1 || process[:pid] == Process.pid
    begin
      Process.kill(signal, process[:pid])
    rescue Errno::ESRCH
      nil
    rescue Errno::EPERM => error
      warn "Cannot signal owned pid #{process[:pid]}: #{error.message}"
    end
  end
end

def verify_square(path, n)
  MetaflipTensorVerifier.verify(path, n, n, n)
end

def mean(values)
  values.empty? ? nil : values.sum.to_f / values.length
end

def summarize(samples, phases, final_status, warmup, workers)
  steady = samples.select { |sample| sample[:status] && sample[:status].fetch("elapsed", "0").to_i >= warmup }
  statuses = steady.filter_map { |sample| sample[:status] }.uniq { |status| status["sequence"] }
  status_begin, status_end = statuses.first, statuses.last
  moves_per_second = nil
  if status_begin && status_end && status_end.fetch("updated_ms").to_i > status_begin.fetch("updated_ms").to_i
    moves_per_second = (status_end.fetch("moves").to_i - status_begin.fetch("moves").to_i) * 1000.0 /
                       (status_end.fetch("updated_ms").to_i - status_begin.fetch("updated_ms").to_i)
  end
  cpu_samples = steady.select { |sample| sample[:cpu_seconds] && sample.fetch(:rss_kib, 0).positive? }
  cpu_start, cpu_end = cpu_samples.first, cpu_samples.last
  cpu_cores = cpu_start && cpu_end && cpu_end[:wall_seconds] > cpu_start[:wall_seconds] ?
                (cpu_end[:cpu_seconds] - cpu_start[:cpu_seconds]) / (cpu_end[:wall_seconds] - cpu_start[:wall_seconds]) : nil
  rss_slope = cpu_start && cpu_end && cpu_end[:wall_seconds] > cpu_start[:wall_seconds] ?
                (cpu_end[:rss_kib] - cpu_start[:rss_kib]) * 60.0 / 1024 / (cpu_end[:wall_seconds] - cpu_start[:wall_seconds]) : nil

  campaign_start = phases.empty? ? 0 : phases.first[:wall_seconds] -
                   (phases.first.fetch("barrier_ms") + phases.first.fetch("coordinator_ms")) / 1000.0
  eligible = phases.select do |phase|
    phase[:wall_seconds] - (phase.fetch("barrier_ms") + phase.fetch("coordinator_ms")) / 1000.0 >= campaign_start + warmup
  end
  totals = (["barrier_ms", "coordinator_ms", "worker_wall_sum_ms"] + PHASE_KEYS).to_h do |key|
    [key, eligible.sum { |phase| phase.fetch(key, 0) }]
  end
  wall_ms = totals.fetch("barrier_ms") + totals.fetch("coordinator_ms")
  slots_ms = workers * wall_ms
  worker_fraction = slots_ms.positive? ? totals.fetch("worker_wall_sum_ms").to_f / slots_ms : nil
  # In async mode workers overlap the coordinator; a barrier-based imbalance
  # calculation is meaningless (and can become negative). Keep it sync-only.
  asynchronous = eligible.any? { |phase| phase.fetch("async", 0) != 0 }
  imbalance_fraction = !asynchronous && slots_ms.positive? ? (workers * totals.fetch("barrier_ms") - totals.fetch("worker_wall_sum_ms")).to_f / slots_ms : nil
  coordinator_fraction = wall_ms.positive? ? totals.fetch("coordinator_ms").to_f / wall_ms : nil
  largest_gap = samples.each_cons(2).map { |a, b| b[:wall_seconds] - a[:wall_seconds] }.max || 0
  {
    moves_per_second_after_warmup: moves_per_second,
    status_interval_ms: status_begin && status_end ? status_end.fetch("updated_ms").to_i - status_begin.fetch("updated_ms").to_i : nil,
    main_cpu_cores_after_warmup: cpu_cores,
    main_cpu_seconds_last_sample: samples.reverse.find { |sample| sample[:cpu_seconds] && sample.fetch(:rss_kib, 0).positive? }&.fetch(:cpu_seconds),
    peak_main_rss_kib: samples.filter_map { |sample| sample[:rss_kib] }.max,
    rss_mib_per_minute_after_warmup: rss_slope,
    system_gpu_utilization_percent_mean: mean(steady.filter_map { |sample| sample[:gpu_percent] }),
    measured_phase_rounds: eligible.length,
    max_sampling_gap_seconds: largest_gap,
    worker_wall_occupancy_fraction: worker_fraction,
    barrier_imbalance_fraction: imbalance_fraction,
    coordinator_fraction: coordinator_fraction,
    phase_totals_ms: totals,
    phase_share_of_wall: PHASE_KEYS.to_h { |key| [key, wall_ms.positive? ? totals.fetch(key).to_f / wall_ms : nil] },
    final_status: final_status
  }
end

def write_aggregate(directory, results)
  metrics = %i[moves_per_second_after_warmup main_cpu_cores_after_warmup worker_wall_occupancy_fraction
               barrier_imbalance_fraction coordinator_fraction peak_main_rss_kib system_gpu_utilization_percent_mean]
  aggregate = results.group_by { |result| result[:allocation] || result.fetch(:target_ms) }.sort.to_h do |target, group|
    values = metrics.to_h do |metric|
      samples = group.filter_map { |result| result[metric] }
      [metric, { mean: mean(samples), min: samples.min, max: samples.max }]
    end
    [target, { repetitions: group.length, metrics: values }]
  end
  File.write(File.join(directory, "aggregate.json"), JSON.pretty_generate(aggregate))
end

options = {
  binary: "/private/tmp/metaflip-coreml-measurements/metaflip-telemetry",
  runtime_root: "/Users/erik/tungsten/bits/tungsten-metaflip/lib/metaflip",
  output: "/private/tmp/metaflip-coreml-measurements/epochs",
  seconds: 20, warmup: 5, workers: 16,
  targets: [250, 500, 1000, 2000, 2000, 1000, 500, 250],
  expected_sha: nil
}
OptionParser.new do |parser|
  parser.banner = "Usage: bench_cpu_epochs.rb [options]"
  parser.on("--binary PATH") { |value| options[:binary] = File.expand_path(value) }
  parser.on("--baseline-binary PATH") { |value| options[:baseline_binary] = File.expand_path(value) }
  parser.on("--baseline-sha SHA") { |value| options[:baseline_sha] = value }
  parser.on("--runtime-root PATH") { |value| options[:runtime_root] = File.expand_path(value) }
  parser.on("--output PATH") { |value| options[:output] = File.expand_path(value) }
  parser.on("--seconds N", Integer) { |value| options[:seconds] = value }
  parser.on("--warmup N", Integer) { |value| options[:warmup] = value }
  parser.on("--targets LIST") { |value| options[:targets] = value.split(",").map { |item| Integer(item, 10) } }
  parser.on("--schedulers LIST", "Matched sync/async order, e.g. sync,async,async,sync") do |value|
    options[:schedulers] = value.split(",")
    raise "scheduler must be baseline, sync or async" unless options[:schedulers].all? { |item| %w[baseline sync async].include?(item) }
  end
  parser.on("--allocations LIST", "CPU:CoreML host workers, e.g. 16:0,16:1,15:1,14:2,12:4") do |value|
    options[:allocations] = value.split(",").map do |item|
      cpu, host = item.split(":").map { |number| Integer(number, 10) }
      raise "invalid CPU:CoreML allocation" unless cpu && cpu.positive? && [0, 1, 2, 4].include?(host)
      { cpu: cpu, host: host }
    end
  end
  parser.on("--model PATH") { |value| options[:model] = File.expand_path(value) }
  parser.on("--helper PATH") { |value| options[:helper] = File.expand_path(value) }
  parser.on("--compute MODE") { |value| options[:compute] = value }
  parser.on("--expected-sha SHA") { |value| options[:expected_sha] = value }
  parser.on("--verify PATH", "Verify one 5x5 checkpoint and exit without running a search") { |value| options[:verify] = File.expand_path(value) }
  parser.on("--summarize PATH", "Recompute an existing sweep's summaries without running a search") { |value| options[:summarize] = File.expand_path(value) }
end.parse!
if options[:verify]
  puts JSON.pretty_generate(verify_square(options[:verify], 5))
  exit(0)
end
if options[:summarize]
  directory = options[:summarize]
  manifest = JSON.parse(File.read(File.join(directory, "manifest.json")))
  results = Dir.glob(File.join(directory, "[0-9]*", "result.json")).sort.map do |path|
    previous = JSON.parse(File.read(path)).transform_keys(&:to_sym)
    samples = JSON.parse(File.read(File.join(File.dirname(path), "samples.json"))).map { |sample| sample.transform_keys(&:to_sym) }
    phases = JSON.parse(File.read(File.join(File.dirname(path), "phases.json"))).map do |phase|
      phase[:wall_seconds] = phase.delete("wall_seconds")
      phase
    end
    result = previous.merge(summarize(samples, phases, previous.fetch(:final_status), manifest.fetch("warmup"), previous.fetch(:workers, manifest.fetch("workers"))))
    command = JSON.parse(File.read(File.join(File.dirname(path), "command.json"))).fetch("command")
    run_tag = command.fetch(command.index("--run-tag") + 1)
    result[:post_sweep_descendants] = owned_processes(previous.fetch(:pid), run_tag, {})
    File.write(path, JSON.pretty_generate(result))
    result
  end
  File.write(File.join(directory, "results.json"), JSON.pretty_generate(results))
  write_aggregate(directory, results)
  raise "live sweep descendants remain; inspect results.json" if results.any? { |result| !result.fetch(:post_sweep_descendants).empty? }
  puts "Recomputed #{results.length} summaries: #{directory}"
  exit(0)
end
raise "seconds must exceed warmup >= 0" unless options[:seconds] > options[:warmup] && options[:warmup] >= 0
raise "targets must be nonnegative" unless options[:targets].all? { |target| target >= 0 }
if options[:allocations]&.any? { |allocation| allocation[:host].positive? }
  raise "allocations require --model and --helper" unless options[:model] && File.exist?(options[:model]) && options[:helper] && File.executable?(options[:helper])
  options[:compute] ||= "cpuAndNeuralEngine"
  raise "invalid compute mode" unless %w[cpuOnly cpuAndNeuralEngine].include?(options[:compute])
end
actual_sha = Digest::SHA256.file(options[:binary]).hexdigest
# The binary digest is recorded in every sweep manifest; pinning it is opt-in
# via --expected-sha so a freshly built tree can always run the benchmark.
raise "binary SHA mismatch: #{actual_sha}" if options[:expected_sha] && actual_sha != options[:expected_sha]
if options[:schedulers]&.include?("baseline")
  raise "baseline requires binary and expected SHA" unless options[:baseline_binary] && options[:baseline_sha]
  raise "baseline SHA mismatch" unless Digest::SHA256.file(options[:baseline_binary]).hexdigest == options[:baseline_sha]
end
raise "output directory is not empty" if File.directory?(options[:output]) && !Dir.empty?(options[:output])
FileUtils.mkdir_p(options[:output])
manifest = options.merge(binary_sha256: actual_sha, started_at: Time.now.utc.iso8601,
                         notes: "Wall-time worker occupancy is not OS CPU utilization; GPU is system-wide. CPU/RSS samples cover the main fleet process, excluding its GPU host children.")
File.write(File.join(options[:output], "manifest.json"), JSON.pretty_generate(manifest))

results = []
trials = if options[:schedulers]
           options[:schedulers].map { |scheduler| { cpu: options[:workers], host: 0, target: options[:targets].first, scheduler: scheduler } }
         elsif options[:allocations]
           options[:allocations].map { |allocation| allocation.merge(target: options[:targets].first) }
         else
           options[:targets].map { |target| { cpu: options[:workers], host: 0, target: target } }
         end
trials.each_with_index do |trial, index|
  target, workers, host_workers = trial.values_at(:target, :cpu, :host)
  allocation = options[:allocations] ? "cpu#{workers}-ml#{host_workers}" : nil
  allocation = trial[:scheduler] if trial[:scheduler]
  suffix = allocation ? "-#{allocation}" : ""
  directory = File.join(options[:output], format("%02d-%dms%s", index + 1, target, suffix))
  FileUtils.mkdir_p(directory)
  state_dir = File.join(directory, "state")
  run_tag = "epoch-#{Process.pid}-#{index + 1}-#{target}#{suffix}"
  status_path = File.join(state_dir, "runs/gf2/5x5x5", run_tag, "status.txt")
  best_path = File.join(state_dir, "checkpoints/gf2/5x5x5/best.txt")
  trial_binary = trial[:scheduler] == "baseline" ? options[:baseline_binary] : options[:binary]
  command = [trial_binary, "--tensor", "5x5", "-J", workers.to_s,
             "--no-tui", "--quiet", "--secs", options[:seconds].to_s,
             "--runtime-root", options[:runtime_root], "--state-dir", state_dir, "--run-tag", run_tag]
  if host_workers.positive?
    command.concat(["--coreml-model", options[:model], "--coreml-helper", options[:helper],
                    "--coreml-workers", host_workers.to_s, "--coreml-compute", options[:compute]])
  end
  environment = { "METAFLIP_PHASE_TIMING" => "1", "METAFLIP_CPU_EPOCH_MS" => target.to_s,
                  "METAFLIP_HOME" => state_dir, "METAFLIP_TUNGSTEN" => "/Users/erik/tungsten/bin/tungsten" }
  environment["METAFLIP_CPU_SCHEDULER"] = trial[:scheduler] == "baseline" ? "sync" : trial[:scheduler]
  initial_power = power_source
  File.write(File.join(directory, "command.json"), JSON.pretty_generate(command: command, environment: environment, binary_sha256: Digest::SHA256.file(trial_binary).hexdigest, power_source: initial_power))
  samples = []
  phases = []
  output_read, output_write = IO.pipe
  started = monotonic
  pid = Process.spawn(environment, *command, out: output_write, err: output_write, pgroup: true)
  output_write.close
  reader = Thread.new do
    File.open(File.join(directory, "run.log"), "w") do |log|
      output_read.each_line do |line|
        log.write(line)
        log.flush
        next unless line.start_with?("METAFLIP_PHASE ")
        phase = fields(line).transform_values { |value| Integer(value, 10) }
        phase[:wall_seconds] = monotonic - started
        raise "phase accounting mismatch" unless PHASE_KEYS.sum { |key| phase.fetch(key, 0) } == phase.fetch("coordinator_ms")
        phases << phase
      end
    end
  end
  puts "START #{index + 1}/#{trials.length} target=#{target}ms cpu=#{workers} ml=#{host_workers} pid=#{pid}"
  STDOUT.flush
  process_status = nil
  timed_out = false
  cleanup_members = []
  owned_seen = {}
  begin
    loop do
      sample = { wall_seconds: monotonic - started, status: read_status(status_path) }.merge(sample_process(pid))
      sample[:gpu_percent] = sample_gpu
      sample[:descendants] = owned_processes(pid, run_tag, owned_seen).reject { |process| process[:pid] == pid }
      sample[:helper_cpu] = sample[:descendants].filter_map do |process|
        next unless options[:helper] && process[:command].start_with?(options[:helper])
        { pid: process[:pid] }.merge(sample_process(process[:pid]))
      end
      samples << sample
      waited = Process.waitpid2(pid, Process::WNOHANG)
      if waited
        process_status = waited[1]
        break
      end
      if monotonic - started > options[:seconds] + 45
        timed_out = true
        signal_owned(pid, run_tag, owned_seen, "TERM")
        break
      end
      sleep(1)
    end
  ensure
    if process_status.nil?
      signal_owned(pid, run_tag, owned_seen, "TERM")
      deadline = monotonic + 5
      while monotonic < deadline
        waited = Process.waitpid2(pid, Process::WNOHANG)
        if waited
          process_status = waited[1]
          break
        end
        sleep(0.1)
      end
      if process_status.nil?
        signal_owned(pid, run_tag, owned_seen, "KILL")
        _, process_status = Process.waitpid2(pid)
      end
    end
    cleanup_members = owned_processes(pid, run_tag, owned_seen)
    unless cleanup_members.empty?
      signal_owned(pid, run_tag, owned_seen, "TERM")
      sleep(0.2)
      signal_owned(pid, run_tag, owned_seen, "KILL") unless owned_processes(pid, run_tag, owned_seen).empty?
    end
    reader.join(5)
    output_read.close unless output_read.closed?
  end
  remaining = owned_processes(pid, run_tag, owned_seen)
  final_status = read_status(status_path)
  verification = File.file?(best_path) ? verify_square(best_path, 5) : { exact: false }
  coreml_log = File.join(File.dirname(status_path), "coreml.log")
  model_events = File.file?(coreml_log) ? File.readlines(coreml_log).filter_map { |line| JSON.parse(line) rescue nil } : []
  coreml_summary = File.readlines(File.join(directory, "run.log")).grep(/^METAFLIP_COREML /).last
  result = summarize(samples, phases, final_status, options[:warmup], workers).merge(
    index: index + 1, target_ms: target, pid: pid, wall_seconds: monotonic - started,
    allocation: allocation, workers: workers, coreml_workers: host_workers,
    power_source_start: initial_power, power_source_end: power_source,
    coreml_summary: fields(coreml_summary), coreml_events: model_events,
    exit_status: process_status.exitstatus, timed_out: timed_out, cleaned_descendants: cleanup_members,
    remaining_descendants: remaining, verification: verification
  )
  File.write(File.join(directory, "samples.json"), JSON.pretty_generate(samples))
  File.write(File.join(directory, "phases.json"), JSON.pretty_generate(phases))
  File.write(File.join(directory, "result.json"), JSON.pretty_generate(result))
  results << result
  File.write(File.join(options[:output], "results.json"), JSON.pretty_generate(results))
  puts "DONE target=#{target}ms moves/s=#{result[:moves_per_second_after_warmup]&.round} CPU=#{result[:main_cpu_cores_after_warmup]&.round(2)} worker_fraction=#{result[:worker_wall_occupancy_fraction]&.round(3)} coordinator=#{result[:coordinator_fraction]&.round(3)} exact=#{verification[:exact]}"
  STDOUT.flush
  raise "trial did not finish cleanly; see #{directory}" unless process_status.success? && !timed_out && remaining.empty? && verification[:exact] && final_status && final_status["producer_state"] == "DONE" && final_status["gpu_degraded"] == "0"
  raise "sleep/power transition invalidated measurement; see #{directory}" unless result[:max_sampling_gap_seconds] < 5 && result[:power_source_start] == result[:power_source_end]
  if host_workers.positive?
    summary = result.fetch(:coreml_summary)
    raise "Core ML did not complete valid batches; see #{coreml_log}" unless summary.fetch("batches", "0").to_i.positive? && summary.fetch("failures", "-1") == "0"
  end
end
write_aggregate(options[:output], results)
puts "Completed #{results.length} runs: #{options[:output]}"
