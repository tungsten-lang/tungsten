#!/usr/bin/env ruby
# frozen_string_literal: true

# Compare the product `run` path (lower -> WIRE -> LLVM -> cached native
# binary) with the explicitly selected legacy tree-walker. The runtime archive
# is primed with a different source before the cold measurement, so "cold
# WIRE" measures this program's lowering/link rather than first-ever toolchain
# setup. Warm samples alternate order to reduce drift bias.

require "digest"
require "open3"
require "optparse"
require "tmpdir"

ROOT = File.expand_path("..", __dir__)
DEFAULT_SOURCE = File.join(ROOT, "benchmarks/compiler/wire_run_modes.w")
PRIME_SOURCE = File.join(ROOT, "compiler/test/fixtures/hello.w")

options = {
  compiler: ENV.fetch("TUNGSTEN_BENCH_COMPILER", File.join(ROOT, "bin/tungsten-compiler")),
  iterations: 500_000,
  runs: 9,
  source: DEFAULT_SOURCE
}

OptionParser.new do |parser|
  parser.banner = "Usage: scripts/bench-wire-run.rb [options]"
  parser.on("--compiler PATH", "compiled compiler to benchmark") { |v| options[:compiler] = v }
  parser.on("--iterations N", Integer, "loop iterations (default: 500000)") { |v| options[:iterations] = v }
  parser.on("--runs N", Integer, "samples per warm mode (default: 9)") { |v| options[:runs] = v }
  parser.on("--source PATH", "benchmark source (default: deterministic compiler fixture)") { |v| options[:source] = v }
end.parse!

abort "--runs must be positive" unless options[:runs].positive?
abort "--iterations must be positive" unless options[:iterations].positive?

compiler = File.expand_path(options[:compiler])
source = File.expand_path(options[:source])
abort "compiler is not executable: #{compiler}" unless File.executable?(compiler)
abort "benchmark source does not exist: #{source}" unless File.file?(source)

def timed_capture(env, argv, root)
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  stdout, stderr, status = Open3.capture3(env, *argv, chdir: root)
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  [elapsed, stdout, stderr, status]
end

def checked_capture(env, argv, root, label)
  elapsed, stdout, stderr, status = timed_capture(env, argv, root)
  return [elapsed, stdout] if status.success?

  warn "#{label} failed (exit #{status.exitstatus})"
  warn stderr unless stderr.empty?
  warn stdout unless stdout.empty?
  exit 1
end

def median(values)
  sorted = values.sort
  middle = sorted.length / 2
  return sorted[middle] if sorted.length.odd?

  (sorted[middle - 1] + sorted[middle]) / 2.0
end

def spread(values, center)
  median(values.map { |value| (value - center).abs })
end

def format_seconds(value)
  format("%.3fs", value)
end

Dir.mktmpdir("tungsten-wire-run-bench") do |tmp|
  cache = File.join(tmp, "cache")
  env = {
    "TUNGSTEN_ROOT" => ROOT,
    "TUNGSTEN_CACHE_DIR" => cache,
    "TUNGSTEN_INCREMENTAL" => "1",
    "TUNGSTEN_LL_DIR" => nil,
    "TUNGSTEN_LL_DONE_MARKER" => nil,
    "TUNGSTEN_LL_PATH" => nil,
    "TUNGSTEN_STOP_AFTER_LOAD_PARSE" => nil
  }
  wire = [compiler, "run", source, "--", options[:iterations].to_s]
  interpret = [compiler, "run", "--interpret", source, "--", options[:iterations].to_s]

  # Prime only the runtime archive and loader state. The target source has a
  # distinct absolute path, so its first WIRE run remains an incremental miss.
  checked_capture(env, [compiler, "run", PRIME_SOURCE], ROOT, "runtime prime")

  cold_time, cold_output = checked_capture(env, wire, ROOT, "cold WIRE run")
  _warmup_time, wire_output = checked_capture(env, wire, ROOT, "warm WIRE run")
  _interpret_warmup, interpret_output = checked_capture(env, interpret, ROOT, "interpreter warmup")

  unless cold_output == wire_output && wire_output == interpret_output
    warn "output parity failed"
    warn "cold WIRE: #{cold_output.inspect}"
    warn "warm WIRE: #{wire_output.inspect}"
    warn "--interpret: #{interpret_output.inspect}"
    exit 1
  end

  samples = { wire: [], interpret: [] }
  options[:runs].times do |index|
    order = index.even? ? %i[wire interpret] : %i[interpret wire]
    order.each do |mode|
      argv = mode == :wire ? wire : interpret
      elapsed, output = checked_capture(env, argv, ROOT, "#{mode} sample #{index + 1}")
      abort "#{mode} output changed during sampling" unless output == wire_output
      samples[mode] << elapsed
    end
  end

  wire_median = median(samples[:wire])
  interpret_median = median(samples[:interpret])
  wire_mad = spread(samples[:wire], wire_median)
  interpret_mad = spread(samples[:interpret], interpret_median)

  puts "WIRE run vs --interpret"
  puts "  source:       #{source}"
  puts "  iterations:   #{options[:iterations]}"
  puts "  samples:      #{options[:runs]} per warm mode (alternating order)"
  puts "  compiler:     #{compiler}"
  puts "  compiler sha: #{Digest::SHA256.file(compiler).hexdigest}"
  puts "  output:       #{wire_output.strip.inspect} (exact parity)"
  puts
  puts format("  %-18s %10s %10s %10s", "mode", "median", "MAD", "range")
  puts format("  %-18s %10s %10s %10s", "WIRE cold", format_seconds(cold_time), "n/a", "one run")
  puts format(
    "  %-18s %10s %10s %10s",
    "WIRE cache hit",
    format_seconds(wire_median),
    format_seconds(wire_mad),
    "#{format_seconds(samples[:wire].min)}-#{format_seconds(samples[:wire].max)}"
  )
  puts format(
    "  %-18s %10s %10s %10s",
    "--interpret",
    format_seconds(interpret_median),
    format_seconds(interpret_mad),
    "#{format_seconds(samples[:interpret].min)}-#{format_seconds(samples[:interpret].max)}"
  )
  puts
  puts format("  warm speedup: %.2fx (--interpret / WIRE cache hit)", interpret_median / wire_median)
end
