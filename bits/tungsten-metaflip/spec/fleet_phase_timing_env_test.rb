#!/usr/bin/env ruby
# Focused native CLI smoke: no GPU, two tiny walkers, one exact-gated round.
# Usage: ruby spec/fleet_phase_timing_env_test.rb /path/to/metaflip [runtime-root]
require "fileutils"
require "open3"
require "tmpdir"

binary = File.expand_path(ARGV.fetch(0))
runtime_root = File.expand_path(ARGV[1] || File.join(__dir__, ".."))
raise "native executable not found: #{binary}" unless File.executable?(binary)

def expect(condition, message)
  raise message unless condition
end

Dir.mktmpdir("metaflip-phase-env-") do |directory|
  run = lambda do |name, timing, override, scheduler = nil, workers = 2|
    environment = {
      "METAFLIP_PHASE_TIMING" => timing,
      "METAFLIP_CPU_EPOCH_MS" => override,
      "METAFLIP_CPU_SCHEDULER" => scheduler,
      "METAFLIP_HOME" => File.join(directory, name)
    }
    command = [binary, "--runtime-root", runtime_root, "--tensor", "2x2",
               "-J", workers.to_s, "--steps", "1000", "--rounds", "1", "--secs", "0",
               "--no-gpu", "--no-tui", "--naive", "--state-dir",
               File.join(directory, name), "--run-tag", name]
    output, status = Open3.capture2e(environment, *command)
    [output, status]
  end

  output, status = run.call("default", nil, nil)
  expect(status.success?, "default failed: #{output}")
  expect(output.include?("cpu_epoch_target_ms=0"), "tiny default cadence changed")
  expect(!output.include?("METAFLIP_PHASE "), "phase timing must default off")

  [["timed-default", nil, 0], ["zero", "0", 0], ["positive", "500", 500]].each do |name, override, target|
    output, status = run.call(name, "1", override)
    expect(status.success?, "#{name} failed: #{output}")
    expect(output.include?("cpu_epoch_target_ms=#{target}"), "#{name}: startup override missing")
    records = output.lines.grep(/^METAFLIP_PHASE /)
    expect(records.length == 1, "#{name}: expected one phase record: #{output}")
    fields = records.first.split.drop(1).to_h { |field| key, value = field.split("=", 2); [key, Integer(value, 10)] }
    expect(fields.fetch("epoch_target_ms") == target, "#{name}: effective target differs")
    expect(fields.fetch("workers") == 2 && fields.fetch("round") == 0, "#{name}: wrong epoch identity")
    expect(fields.fetch("async") == 0 && fields.fetch("inflight") == 0, "#{name}: tiny default must drain synchronously")
    expect(fields.values.all? { |value| value >= 0 }, "#{name}: negative phase measurement")
    phase_sum = %w[controls_ms intake_ms leases_ms harvest_ms reseeds_ms launch_ms status_ms].sum { |key| fields.fetch(key) }
    expect(phase_sum == fields.fetch("coordinator_ms"), "#{name}: phase sum differs from coordinator wall time")
    expect(fields.fetch("worker_wall_max_ms") <= fields.fetch("barrier_ms"), "#{name}: worker exceeds barrier wall time")
    expect(fields.fetch("worker_wall_sum_ms") >= fields.fetch("worker_wall_max_ms"), "#{name}: worker sum below maximum")
    expect(!output.match?(/exact_bad=[1-9]/), "#{name}: exact verification rejected a CPU endpoint")
  end

  ["oops", "-1", "9223372036854775808"].each_with_index do |override, index|
    output, status = run.call("invalid-#{index}", "1", override)
    expect(status.exitstatus == 2, "#{override.inspect}: invalid override did not exit 2: #{output}")
    expect(output.include?("METAFLIP_CPU_EPOCH_MS"), "#{override.inspect}: diagnostic missing environment name")
    expect(!output.include?("METAFLIP_PHASE "), "#{override.inspect}: invalid override ran an epoch")
  end

  %w[sync async].each do |scheduler|
    output, status = run.call("scheduler-#{scheduler}", "1", "50", scheduler)
    expect(status.success?, "#{scheduler}: scheduler override failed: #{output}")
    mode = scheduler == "async" ? 1 : 0
    records = output.lines.grep(/^METAFLIP_PHASE /)
    expect(records.any? { |line| line.include?("async=#{mode}") }, "#{scheduler}: wrong mode")
    expect(records.last.include?("inflight=0"), "#{scheduler}: final epochs not drained")
  end
  output, status = run.call("invalid-scheduler", "1", "50", "oops")
  expect(status.exitstatus == 2 && output.include?("METAFLIP_CPU_SCHEDULER"), "invalid scheduler was not rejected: #{output}")
  expect(!output.include?("METAFLIP_PHASE "), "invalid scheduler ran an epoch")
  output, status = run.call("wide-default", "1", "0", nil, 8)
  expect(status.success?, "wide default failed: #{output}")
  expect(output.lines.grep(/^METAFLIP_PHASE /).all? { |line| line.include?("async=0") && line.include?("inflight=0") }, "wide default changed scheduling mode")
end

puts "PASS fleet phase timing: defaults, cadence/scheduler overrides, invalid values, wall-time accounting"
