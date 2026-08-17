#!/usr/bin/env ruby
# frozen_string_literal: true

# End-to-end Qwen3.8/27B-MLX autotune harness. The Tungsten kernel tuner
# measures individual real-weight shapes; this wrapper evaluates the resulting
# row schedules in both ordinary and MTP-1 decode and refuses candidates whose
# greedy output differs from the first run.

require "open3"

ROOT = File.expand_path("../..", __dir__)
TUNGSTEN = ENV.fetch("TUNGSTEN", File.join(ROOT, "bin/tungsten"))
RUNNER = File.join(ROOT, "scripts/bench/qwen38_mlx.w")
KERNEL_TUNER = File.join(ROOT, "scripts/bench/autotune_qwen38.w")

TOKENS = Integer(ENV.fetch("TOKENS", "24"))
WARMUPS = Integer(ENV.fetch("WARMUPS", "1"))
RUNS = Integer(ENV.fetch("RUNS", "3"))
SCHEDULES = ENV.fetch("SCHEDULES", "4r,8r,16r,r2,auto").split(",").map(&:strip).reject(&:empty?).freeze
MODES = ENV.fetch("MODES", "concurrent,mtp").split(",").map(&:strip).reject(&:empty?).freeze
MTP_VARIANTS = ENV.fetch("MTP_VARIANTS", "optimized").split(",").map(&:strip).reject(&:empty?).freeze

def median(values)
  sorted = values.sort
  middle = sorted.length / 2
  sorted.length.odd? ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2.0
end

def run_candidate(mode, schedule, mtp_variant)
  command = [TUNGSTEN, "run", RUNNER, mode, TOKENS.to_s, schedule, "mmap"]
  if mode == "mtp"
    argument = {
      "optimized" => nil,
      "legacy" => "legacy-mtp",
      "full-vocab" => "full-draft-vocab",
      "full-history" => "full-history"
    }.fetch(mtp_variant) do
      raise "unknown MTP variant #{mtp_variant.inspect}"
    end
    command << argument if argument
  end
  stdout, stderr, status = Open3.capture3(*command, chdir: ROOT)
  unless status.success?
    raise "#{command.join(" ")} failed (#{status.exitstatus})\n#{stdout}\n#{stderr}"
  end

  rate = stdout[/decode: .*?, ([0-9.eE+-]+) tok\/s/, 1]
  ids = stdout[/^generated ids: (.+)$/, 1]
  acceptance = stdout[/^mtp: (.+)$/, 1]
  raise "missing decode rate for #{mode}/#{schedule}\n#{stdout}" unless rate
  raise "missing generated ids for #{mode}/#{schedule}\n#{stdout}" unless ids

  { rate: Float(rate), ids: ids, acceptance: acceptance }
end

puts "Qwen3.8/27B-MLX model autotune"
puts [
  "tokens=#{TOKENS}", "warmups=#{WARMUPS}", "runs=#{RUNS}",
  "modes=#{MODES.join(",")}",
  "schedules=#{SCHEDULES.join(",")}",
].join(" ")
puts "mtp_variants=#{MTP_VARIANTS.join(",")}" if MODES.include?("mtp")

if ENV.fetch("KERNELS", "1") != "0"
  puts
  puts "Kernel-shape sweep"
  system(TUNGSTEN, "run", KERNEL_TUNER, chdir: ROOT) || abort("kernel autotune failed")
end

reference_ids = nil
results = []

MODES.each do |mode|
  variants = mode == "mtp" ? MTP_VARIANTS : ["default"]
  variants.each do |variant|
    SCHEDULES.each do |schedule|
      label = mode == "mtp" ? "#{mode}/#{variant}/#{schedule}" : "#{mode}/#{schedule}"
      WARMUPS.times do |index|
        sample = run_candidate(mode, schedule, variant)
        reference_ids ||= sample[:ids]
        raise "greedy output mismatch for #{label} warmup" unless sample[:ids] == reference_ids
        puts "#{label} warmup #{index + 1}/#{WARMUPS}: %.3f tok/s%s" % [
          sample[:rate],
          sample[:acceptance] ? " (#{sample[:acceptance]})" : ""
        ]
      end

      rates = []
      acceptance = nil
      RUNS.times do |index|
        sample = run_candidate(mode, schedule, variant)
        reference_ids ||= sample[:ids]
        raise "greedy output mismatch for #{label} run #{index + 1}" unless sample[:ids] == reference_ids
        rates << sample[:rate]
        acceptance = sample[:acceptance] if sample[:acceptance]
        puts "#{label} run #{index + 1}/#{RUNS}: %.3f tok/s%s" % [
          sample[:rate],
          sample[:acceptance] ? " (#{sample[:acceptance]})" : ""
        ]
      end
      results << {
        mode: mode, variant: variant, schedule: schedule,
        median: median(rates), rates: rates, acceptance: acceptance
      }
    end
  end
end

puts
puts "Ranked candidates"
results.sort_by { |result| -result[:median] }.each do |result|
  puts "%-18s median=%8.3f tok/s samples=%s%s" % [
    result[:mode] == "mtp" ?
      "#{result[:mode]}/#{result[:variant]}/#{result[:schedule]}" :
      "#{result[:mode]}/#{result[:schedule]}",
    result[:median],
    result[:rates].map { |rate| format("%.3f", rate) }.join(","),
    result[:acceptance] ? " (#{result[:acceptance]})" : ""
  ]
end

MODES.each do |mode|
  winner = results.select { |result| result[:mode] == mode }.max_by { |result| result[:median] }
  winner_label = mode == "mtp" ? "#{winner[:variant]}/#{winner[:schedule]}" : winner[:schedule]
  puts "best #{mode}: #{winner_label} at %.3f tok/s median" % winner[:median]
end
