#!/usr/bin/env ruby
# Run matched runtime binaries serially in alternating ABBA / BAAB blocks.
# The C harness bounds every cell with alarm(20); this adds a parent watchdog.
require 'json'
require 'open3'
require 'timeout'
require 'digest'
require 'time'

abort "usage: #{$PROGRAM_NAME} BASELINE CANDIDATE OUTPUT.json [BLOCKS=3]" unless (3..4).cover?(ARGV.size)
baseline, candidate, output = ARGV.first(3).map { |p| File.expand_path(p) }
blocks = Integer(ARGV[3] || 3)
abort 'BLOCKS must be positive' unless blocks.positive?

cells = [1, 100, 1000].map { |n| ['idle', n, 200] } +
        [1, 100, 1000].map { |n| ['ready', n, 32] } +
        [1, 1000].map { |n| ['ready-untimed', n, 32] } +
        [1, 100, 1000, 10000].map { |n| ['frontier', n, 10000] }
paths = { 'baseline' => baseline, 'candidate' => candidate }
data = { 'measured_at' => Time.now.utc.iso8601,
         'platform' => RUBY_PLATFORM,
         'runner_sha256' => Digest::SHA256.file(__FILE__).hexdigest,
         'harness_sha256' => Digest::SHA256.file(File.expand_path('../../runtime/bench_event_deadlines.c', __dir__)).hexdigest,
         'binaries' => paths.transform_values { |p| { 'path' => p, 'sha256' => Digest::SHA256.file(p).hexdigest } },
         'blocks' => blocks, 'samples' => [] }

def run_cell(path, cell)
  text = errors = nil
  status = nil
  Open3.popen3(path, *cell.map(&:to_s), pgroup: true) do |input, out, err, child|
    input.close
    begin
      Timeout.timeout(25) do
        stdout = Thread.new { out.read }
        stderr = Thread.new { err.read }
        status = child.value
        text, errors = stdout.value, stderr.value
      end
    rescue Timeout::Error
      Process.kill('KILL', -child.pid) rescue Errno::ESRCH
      raise "cell timed out: #{path} #{cell.join(' ')}"
    end
  end
  raise "cell failed: #{path} #{cell.join(' ')}: #{errors}" unless status.success?
  parsed = JSON.parse(text)
  raise 'incomplete cell' unless parsed.fetch('completed') == cell[1]
  parsed
end

def median(xs)
  sorted = xs.sort
  (sorted[(sorted.size - 1) / 2] + sorted[sorted.size / 2]) / 2.0
end

# Untimed warmup: also fail early if either binary cannot run this corpus.
cells.each { |cell| paths.each_value { |path| run_cell(path, cell) } }
blocks.times do |block|
  cells.rotate(block).each do |cell|
    order = block.even? ? %w[baseline candidate candidate baseline] : %w[candidate baseline baseline candidate]
    order.each do |lane|
      sample = run_cell(paths.fetch(lane), cell)
      data['samples'] << sample.merge('lane' => lane, 'block' => block)
    end
    puts "block #{block + 1}/#{blocks}: #{cell.join(' ')} complete"
    $stdout.flush
  end
end
data['summary'] = cells.map do |mode, n, amount|
  row = { 'mode' => mode, 'waiters' => n, 'amount' => amount }
  %w[wall_ms cpu_ms p50_late_us p99_late_us max_late_us voluntary_switches involuntary_switches].each do |field|
    paths.each_key do |lane|
      xs = data['samples'].select { |s| s['mode'] == mode && s['waiters'] == n && s['lane'] == lane }.map { |s| s.fetch(field) }
      row["#{lane}_#{field}"] = median(xs)
    end
  end
  row['wall_ratio'] = row['candidate_wall_ms'] / row['baseline_wall_ms']
  row['cpu_ratio'] = row['candidate_cpu_ms'] / row['baseline_cpu_ms']
  row
end
File.write(output, JSON.pretty_generate(data) + "\n")
data['summary'].each do |s|
  puts format('%-14s %5d wall %9.3f -> %9.3f ms (%5.2fx), CPU %8.3f -> %8.3f ms, p99 late %8.1f -> %8.1f us',
              s['mode'], s['waiters'], s['baseline_wall_ms'], s['candidate_wall_ms'], s['wall_ratio'],
              s['baseline_cpu_ms'], s['candidate_cpu_ms'], s['baseline_p99_late_us'], s['candidate_p99_late_us'])
end
