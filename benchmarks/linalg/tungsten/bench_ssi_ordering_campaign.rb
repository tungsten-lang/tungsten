#!/usr/bin/env ruby
# frozen_string_literal: true

# Matched fresh-process runner for ssi_ordering_campaign.w.
#
# Each candidate is alternated with AMD so thermal/order drift is shared.  The
# Tungsten allocation profiler is enabled for every child; results are emitted
# as TSV so individual mechanisms can be retained or rejected from evidence.
#
# Usage:
#   ruby benchmarks/linalg/tungsten/bench_ssi_ordering_campaign.rb \
#     --binary /tmp/ssi-ordering-campaign --rounds 5 \
#     --case grid:20 --case random:200 amd amf rgreedy window8

require "open3"
require "optparse"

options = {
  binary: "/tmp/ssi-ordering-campaign",
  rounds: 5,
  budget: 20_000_000,
  stream: 0,
  cases: []
}

OptionParser.new do |opts|
  opts.banner = "usage: #{$PROGRAM_NAME} [options] MODE..."
  opts.on("--binary PATH", "compiled campaign binary") { |v| options[:binary] = v }
  opts.on("--rounds N", Integer, "fresh processes per mode/case") { |v| options[:rounds] = v }
  opts.on("--budget N", Integer, "candidate work budget") { |v| options[:budget] = v }
  opts.on("--stream N", Integer, "deterministic candidate stream") { |v| options[:stream] = v }
  opts.on("--case FAMILY:SIZE", "repeatable graph case") { |v| options[:cases] << v }
end.parse!

modes = ARGV.empty? ? %w[amd amf rgreedy minl window8 telos rgsub] : ARGV
options[:cases] = %w[grid:20 blocks:10 bridge:15 shell:200 random:200] if options[:cases].empty?
abort "missing executable: #{options[:binary]}" unless File.executable?(options[:binary])
abort "rounds must be positive" unless options[:rounds].positive?

def parse_run(binary, mode, family, size, budget, stream, profile: false)
  env = profile ? { "TUNGSTEN_ALLOC_PROFILE" => "1" } : {}
  stdout, stderr, status = Open3.capture3(
    env, binary, mode, family, size.to_s, "1", budget.to_s, stream.to_s
  )
  abort "#{mode}/#{family}:#{size} failed:\n#{stdout}\n#{stderr}" unless status.success?

  line = stdout.lines.find { |entry| entry.start_with?("BENCH ssi_ordering ") }
  abort "missing BENCH line for #{mode}/#{family}:#{size}" unless line

  fields = line.scan(/([a-z_]+)=([^ ]+)/).to_h
  allocs = nil
  bytes = nil
  if profile
    allocs = 0
    bytes = 0
  end
  stderr.each_line do |entry|
    next unless (match = entry.match(/^TALLOC\s+\S+\s+(\d+)\s+(\d+)/))

    allocs += match[1].to_i
    bytes += match[2].to_i
  end
  {
    ns: fields.fetch("ns").to_f,
    fill: fields.fetch("fill").to_i,
    flops: fields.fetch("flops").to_i,
    amd_flops: fields.fetch("amd_flops").to_i,
    checksum: fields.fetch("checksum").to_i,
    allocs: allocs,
    bytes: bytes
  }
end

def median(values)
  sorted = values.sort
  mid = sorted.length / 2
  return sorted[mid] if sorted.length.odd?

  (sorted[mid - 1] + sorted[mid]) / 2.0
end

puts %w[family size mode rounds median_ns min_ns fill flops amd_flops flop_ratio checksum median_allocs median_bytes].join("\t")

options[:cases].each do |spec|
  family, size_text = spec.split(":", 2)
  abort "bad --case #{spec.inspect}; expected FAMILY:SIZE" unless family && size_text&.match?(/\A\d+\z/)

  size = size_text.to_i
  rows = Hash.new { |hash, key| hash[key] = [] }
  # ABBA by round: each non-AMD candidate is bracketed by the common floor.
  options[:rounds].times do |round|
    order = round.even? ? modes : modes.reverse
    order.each do |mode|
      rows[mode] << parse_run(
        options[:binary], mode, family, size, options[:budget], options[:stream]
      )
    end
  end

  rows.each do |mode, samples|
    first = samples.first
    unless samples.all? { |sample| sample.values_at(:fill, :flops, :checksum) == first.values_at(:fill, :flops, :checksum) }
      abort "non-deterministic structural result for #{mode}/#{family}:#{size}"
    end
    # Keep allocation instrumentation out of the timed samples.  One separate
    # deterministic process is sufficient because the structural result is
    # checked above and the profiler counts allocation sites, not retained RSS.
    allocation_sample = parse_run(
      options[:binary], mode, family, size, options[:budget], options[:stream],
      profile: true
    )
    unless allocation_sample.values_at(:fill, :flops, :checksum) == first.values_at(:fill, :flops, :checksum)
      abort "profiled result differs for #{mode}/#{family}:#{size}"
    end
    ratio = first[:flops].fdiv(first[:amd_flops])
    puts [
      family, size, mode, samples.length,
      median(samples.map { |sample| sample[:ns] }).round(1),
      samples.map { |sample| sample[:ns] }.min.round(1),
      first[:fill], first[:flops], first[:amd_flops], format("%.9f", ratio),
      first[:checksum], allocation_sample[:allocs], allocation_sample[:bytes]
    ].join("\t")
  end
end
