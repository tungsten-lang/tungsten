#!/usr/bin/env ruby
# Same-binary, isolated-state rectangular fill comparison and exact replay.
require "fileutils"
require "open3"
require "time"
require_relative "verify_tensor"

def fields(text)
  text.to_s.split.filter_map { |word| key, value = word.split("=", 2); [key, value] if value }.to_h
end

def monotonic
  Process.clock_gettime(Process::CLOCK_MONOTONIC)
end

def processes
  output, = Open3.capture2("/bin/ps", "-axo", "pid=,ppid=,uid=,lstart=,command=")
  output.lines.filter_map do |line|
    v = line.strip.split(/\s+/, 9)
    next unless v.length == 9 && v[2].to_i == Process.uid
    { pid: v[0].to_i, ppid: v[1].to_i, identity: [v[3..7].join(" "), v[8]], command: v[8] }
  end
end

def owned_processes(root, directory, seen)
  all = processes
  owned = all.select do |p|
    p[:pid] != Process.pid && ((p[:pid] == root && p[:command].include?(directory)) || seen[p[:pid]] == p[:identity])
  end
  loop do
    parents = owned.map { |p| p[:pid] }
    children = all.select { |p| parents.include?(p[:ppid]) && !parents.include?(p[:pid]) }
    break if children.empty?
    owned.concat(children)
  end
  owned.each { |p| seen[p[:pid]] = p[:identity] }
  owned
end

def signal_owned(root, directory, seen, signal)
  owned_processes(root, directory, seen).reverse_each do |p|
    next if p[:pid] <= 1
    Process.kill(signal, p[:pid])
  rescue Errno::ESRCH
    nil
  end
end

def gpu_percent
  output, = Open3.capture2("/usr/sbin/ioreg", "-r", "-d", "1", "-c", "AGXAccelerator")
  output[/"Device Utilization %"\s*=\s*(\d+)/, 1]&.to_i
end

def power_source
  output, = Open3.capture2("/usr/bin/pmset", "-g", "batt")
  output.lines.first.to_s.strip
end

options = { seconds: 90, warmup: 20, workers: 16, rounds: 32, axis: "fill",
            shapes: "2x5x6,3x4x6,4x5x6,4x5x7,4x6x7" }
OptionParser.new do |parser|
  parser.banner = "Usage: bench_rect_fills.rb --binary PATH --expected-sha SHA --runtime-root PATH --output PATH [options]"
  %i[binary runtime_root output seed_state expected_sha].each do |key|
    parser.on("--#{key.to_s.tr('_', '-')} VALUE") { |value| options[key] = value }
  end
  %i[seconds warmup workers rounds steps].each do |key|
    parser.on("--#{key} N", Integer) { |value| options[key] = value }
  end
  parser.on("--policies LIST") { |value| options[:policies] = value.split(",") }
  parser.on("--axis NAME", "fill or overlap") { |value| options[:axis] = value }
  parser.on("--shapes LIST") { |value| options[:shapes] = value }
  parser.on("--sample-gpu", "Optional system utilization query; may stall on a busy driver") { options[:sample_gpu] = true }
end.parse!
%i[binary runtime_root output].each { |key| options[key] = File.expand_path(options.fetch(key)) }
raise "unsafe duration/warmup" unless options[:seconds].positive? && options[:warmup] >= 0 && options[:warmup] < options[:seconds]
raise "workers and rounds must be positive" unless options[:workers].positive? && options[:rounds].positive?
raise "invalid comparison axis" unless %w[fill overlap].include?(options[:axis])
allowed_policies = options[:axis] == "fill" ? %w[single batch] : %w[barrier overlap]
options[:policies] ||= allowed_policies + allowed_policies.reverse
raise "invalid policies" unless options[:policies].any? && options[:policies].all? { |p| allowed_policies.include?(p) }
raise "steps must be positive" if options[:steps] && !options[:steps].positive?
options[:shapes].split(",").each { |shape| MetaflipTensorVerifier.dimensions(shape) }
binary_sha = Digest::SHA256.file(options[:binary]).hexdigest
raise "binary hash differs" unless binary_sha == options.fetch(:expected_sha)
raise "use a fresh output directory" if File.exist?(options[:output])
FileUtils.mkdir_p(options[:output])
results = []

options[:policies].each_with_index do |policy, index|
  raise "binary changed between runs" unless Digest::SHA256.file(options[:binary]).hexdigest == binary_sha
  directory = File.join(options[:output], "%02d-%s" % [index + 1, policy])
  state = File.join(directory, "state")
  FileUtils.mkdir_p(state)
  if options[:seed_state]
    FileUtils.cp_r(File.join(options[:seed_state], "checkpoints"), state)
  end
  seed_files = Dir.glob(File.join(state, "checkpoints", "gf2", "*", "*.txt"))
  seeds = seed_files.map { |path| MetaflipTensorVerifier.verify(path, *MetaflipTensorVerifier.dimensions(MetaflipTensorVerifier.infer_shape(path))) }
  status_path = File.join(directory, "status.txt")
  tag = "rect-fill-#{Process.pid}-#{index + 1}-#{policy}"
  command = [options[:binary], "--runtime-root", options[:runtime_root], "--rect", "--rect-shapes", options[:shapes],
             "-J", options[:workers].to_s, "--gpu", "--gpu-walkers", "8192", "--gpu-steps", "40000",
             "--rect-epoch-rounds", options[:rounds].to_s, "--secs", options[:seconds].to_s,
             "--no-tui", "--quiet", "--state-dir", state, "--run-tag", tag, "--status", status_path]
  command += ["--steps", options[:steps].to_s] if options[:steps]
  environment = { "METAFLIP_RECT_FILL" => options[:axis] == "fill" ? policy : "batch",
                  "METAFLIP_RECT_CPU_GPU" => options[:axis] == "overlap" ? policy : "barrier",
                  "METAFLIP_COREML_WORKERS" => nil }
  File.write(File.join(directory, "command.json"), JSON.pretty_generate(command: command, environment: environment, binary_sha256: binary_sha, starting_witnesses: seeds))
  samples = []
  seen = {}
  start_power = power_source
  started = monotonic
  child_times = Process.times
  child_cpu_start = child_times.cutime + child_times.cstime
  pid = Process.spawn(environment, *command, out: File.join(directory, "run.log"), err: [:child, :out])
  caffeinate = Process.spawn("/usr/bin/caffeinate", "-i", "-s", "-w", pid.to_s)
  status = nil
  forced = false
  begin
    loop do
      waited = Process.waitpid2(pid, Process::WNOHANG)
      if waited
        status = waited[1]
        break
      end
      elapsed = monotonic - started
      header = File.file?(status_path) ? fields(File.read(status_path).lines.first) : {}
      query_started = monotonic
      owned_processes(pid, directory, seen)
      process_query_seconds = monotonic - query_started
      query_started = monotonic
      gpu = options[:sample_gpu] ? gpu_percent : nil
      samples << { wall_seconds: elapsed, header: header, gpu_percent: gpu,
                   process_query_seconds: process_query_seconds,
                   gpu_query_seconds: monotonic - query_started }
      if elapsed > options[:seconds] + 120
        forced = true
        signal_owned(pid, directory, seen, "INT")
      end
      if elapsed > options[:seconds] + 135
        signal_owned(pid, directory, seen, "KILL")
        Process.waitpid(pid)
        raise "portfolio did not drain"
      end
      sleep 1
    end
  ensure
    if status.nil?
      signal_owned(pid, directory, seen, "TERM")
      20.times do
        begin
          waited = Process.waitpid2(pid, Process::WNOHANG)
          status = waited[1] if waited
        rescue Errno::ECHILD
          break
        end
        break if status
        sleep 0.1
      end
      signal_owned(pid, directory, seen, "KILL") unless owned_processes(pid, directory, seen).empty?
      begin
        Process.waitpid(pid) unless status
      rescue Errno::ECHILD
        nil
      end
    end
    begin
      Process.kill("TERM", caffeinate)
    rescue Errno::ESRCH
      nil
    end
    begin
      Process.waitpid(caffeinate)
    rescue Errno::ECHILD
      nil
    end
    File.write(File.join(directory, "samples.json"), JSON.pretty_generate(samples))
  end
  wall = monotonic - started
  child_times = Process.times
  # Includes process-sampling helpers and startup/drain, not a steady-state
  # core-occupancy measurement. Short-lived fill children evade ps sampling.
  child_cpu = child_times.cutime + child_times.cstime - child_cpu_start
  leftovers = owned_processes(pid, directory, seen)
  unless leftovers.empty?
    signal_owned(pid, directory, seen, "TERM")
    raise "owned descendants remained after normal exit; sent TERM"
  end
  raise "portfolio failed or forced timeout" unless status.success? && !forced
  header = fields(File.read(status_path).lines.first)
  raise "unhealthy or incomplete portfolio" unless header["producer_state"] == "stopped" && header["health"] == "ok" && header.fetch("total_gpu_moves", "0").to_i.positive?
  raise "power source changed" unless power_source == start_power
  gaps = samples.each_cons(2).map { |a, b| b[:wall_seconds] - a[:wall_seconds] }
  raise "sleep-sized measurement gap" if (gaps.max || 0) > 5
  steady = samples.select { |sample| sample[:wall_seconds] >= options[:warmup] && sample[:header].key?("total_moves") }
  a, b = steady.first, steady.last
  raise "insufficient steady-state samples" unless a && b && b[:wall_seconds] > a[:wall_seconds]
  interval = b[:wall_seconds] - a[:wall_seconds]
  rates = %w[total_moves total_cpu_moves total_gpu_moves].to_h { |key| [key + "_per_second", (b[:header].fetch(key).to_i - a[:header].fetch(key).to_i) / interval] }
  gpu = steady.filter_map { |sample| sample[:gpu_percent] }
  verified = Dir.glob(File.join(state, "checkpoints", "gf2", "*", "*.txt")).map do |path|
    MetaflipTensorVerifier.verify(path, *MetaflipTensorVerifier.dimensions(MetaflipTensorVerifier.infer_shape(path)))
  end
  child_statuses = Dir.glob(status_path + ".*").reject { |path| path.end_with?(".log") }.to_h do |path|
    [File.basename(path), fields(File.read(path))]
  end
  result = { axis: options[:axis], policy: policy, binary_sha256: binary_sha, seconds: wall, child_cpu_seconds_including_sampling: child_cpu,
             rates: rates, system_gpu_percent_mean: gpu.empty? ? nil : gpu.sum.to_f / gpu.size,
             final_status: header, final_child_statuses: child_statuses, exact_witnesses: verified, max_sample_gap: gaps.max, power: start_power }
  File.write(File.join(directory, "result.json"), JSON.pretty_generate(result))
  results << result
  File.write(File.join(options[:output], "results.json"), JSON.pretty_generate(results))
  puts JSON.generate(policy: policy, seconds: wall, rates: rates, exact_witnesses: verified.size, final_status: header)
  $stdout.flush
end
