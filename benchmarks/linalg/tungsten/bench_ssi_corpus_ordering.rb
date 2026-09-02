#!/usr/bin/env ruby
# frozen_string_literal: true

# Reproducible adapter for Tungsten sparse ordering on the public SSI corpus.
# It reads corpus/dev/patterns.jsonl directly, converts CSC to the historical
# flat COO transport in a temporary directory, and runs a fresh Tungsten process
# per timed round.  JSON decoding, conversion, and SparseAnalysis construction
# are excluded from the time reported by the Tungsten runner.
#
# Build the runner:
#   bin/tungsten compile --release --native \
#     --out /tmp/ssi-corpus-ordering \
#     benchmarks/linalg/tungsten/ssi_corpus_ordering.w
#
# Safe default: one round, a gap-enriched six-row suite, and a 100M work budget:
#   ruby benchmarks/linalg/tungsten/bench_ssi_corpus_ordering.rb
#
# Select one or more named rows (repeat --case):
#   ruby benchmarks/linalg/tungsten/bench_ssi_corpus_ordering.rb \
#     --case mpbp_35 --case cont6-qq --rounds 3 --budget 150000000
#
# Select every corpus row with n > 10,000 (intentionally not the default):
#   ruby benchmarks/linalg/tungsten/bench_ssi_corpus_ordering.rb --gt-10k
#
# The archived campaign used --stream 7 --budget 150000000. Keep the
# lower default for smoke tests and profiling setup; pass the archived budget
# explicitly for matched quality comparisons.

require "json"
require "open3"
require "optparse"
require "tmpdir"

DEFAULT_SOURCES = %w[
  ringpack_30_2
  pooling_sppc3pq
  mpbp_35
  cont6-qq
  acopf_case9241pegase_qcqp
  crudeoil_lee4_06
].freeze

options = {
  binary: "/tmp/ssi-corpus-ordering",
  corpus: File.expand_path("~/ssi-ordering-challenge/corpus/dev/patterns.jsonl"),
  rounds: 1,
  budget: 100_000_000,
  stream: 7,
  restarts: nil,
  cases: [],
  gt_10k: false
}

OptionParser.new do |opts|
  opts.banner = "usage: #{$PROGRAM_NAME} [options]"
  opts.on("--binary PATH", "compiled Tungsten runner") { |v| options[:binary] = v }
  opts.on("--corpus PATH", "challenge patterns.jsonl") { |v| options[:corpus] = v }
  opts.on("--rounds N", Integer, "fresh processes per row (default: 1)") { |v| options[:rounds] = v }
  opts.on("--budget N", Integer, "best_ordering work budget (default: 100M)") { |v| options[:budget] = v }
  opts.on("--stream N", Integer, "deterministic search stream (default: 7)") { |v| options[:stream] = v }
  opts.on("--restarts N", Integer, "override archived restart policy") { |v| options[:restarts] = v }
  opts.on("--case SOURCE", "select a source name; repeatable") { |v| options[:cases] << v }
  opts.on("--gt-10k", "select every row with n > 10,000") { options[:gt_10k] = true }
end.parse!

abort "unexpected arguments: #{ARGV.join(' ')}" unless ARGV.empty?
abort "missing executable: #{options[:binary]}" unless File.executable?(options[:binary])
abort "missing corpus: #{options[:corpus]}" unless File.file?(options[:corpus])
abort "--rounds must be positive" unless options[:rounds].positive?
abort "--budget must be non-negative" if options[:budget].negative?
abort "--restarts must be positive" if options[:restarts] && !options[:restarts].positive?
abort "use either --case or --gt-10k, not both" if options[:gt_10k] && !options[:cases].empty?

def corpus_index(path)
  entries = []
  sources = {}
  offset = 0

  File.open(path, "rb") do |io|
    line_number = 0
    while (line = io.gets)
      line_number += 1
      begin
        record = JSON.parse(line)
      rescue JSON::ParserError => e
        abort "invalid JSON at #{path}:#{line_number}: #{e.message}"
      end

      source = record.fetch("source")
      abort "duplicate corpus source: #{source}" if sources.key?(source)

      entry = {
        source: source,
        n: Integer(record.fetch("n")),
        nnz: Integer(record.fetch("nnz")),
        offset: offset,
        length: line.bytesize
      }
      entries << entry
      sources[source] = entry
      offset += line.bytesize
    end
  end

  [entries, sources]
end

def read_record(io, entry)
  io.seek(entry.fetch(:offset))
  raw = io.read(entry.fetch(:length))
  abort "short corpus read for #{entry.fetch(:source)}" unless raw&.bytesize == entry.fetch(:length)

  JSON.parse(raw)
end

def write_flat_pattern(record, path)
  n = Integer(record.fetch("n"))
  stated_nnz = Integer(record.fetch("nnz"))
  indptr = record.fetch("indptr")
  indices = record.fetch("indices")
  abort "indptr length mismatch for #{record.fetch('source')}" unless indptr.length == n + 1
  abort "nnz length mismatch for #{record.fetch('source')}" unless stated_nnz == indices.length
  abort "invalid CSC endpoints for #{record.fetch('source')}" unless indptr.first == 0 && indptr.last == indices.length

  diagonal = 0
  File.open(path, "wb") do |io|
    io.write("#{n} #{indices.length}")
    buffer = +""
    col = 0
    while col < n
      first = indptr[col]
      last = indptr[col + 1]
      abort "non-monotone indptr for #{record.fetch('source')}" if first > last

      pos = first
      while pos < last
        row = indices[pos]
        abort "row index out of range for #{record.fetch('source')}" unless row.between?(0, n - 1)

        diagonal += 1 if row == col
        buffer << " " << row.to_s << " " << col.to_s
        if buffer.bytesize >= 1_048_576
          io.write(buffer)
          buffer.clear
        end
        pos += 1
      end
      col += 1
    end
    io.write(buffer)
    io.write("\n")
  end

  indices.length - diagonal
end

def run_once(binary, flat_path, stream, budget, restarts)
  argv = [binary, flat_path, stream.to_s, budget.to_s]
  argv << restarts.to_s if restarts
  stdout, stderr, status = Open3.capture3(*argv)
  abort "runner failed (#{status.exitstatus}):\n#{stdout}\n#{stderr}" unless status.success?

  line = stdout.lines.find { |entry| entry.start_with?("BENCH ssi_corpus_ordering ") }
  abort "runner did not emit a BENCH ssi_corpus_ordering line:\n#{stdout}\n#{stderr}" unless line

  fields = line.scan(/([a-z_]+)=([^ ]+)/).to_h
  {
    n: Integer(fields.fetch("n")),
    nnz: Integer(fields.fetch("nnz")),
    restarts: Integer(fields.fetch("restarts")),
    stream: Integer(fields.fetch("stream")),
    budget: Integer(fields.fetch("budget")),
    ns: Float(fields.fetch("ns")),
    fill: Integer(fields.fetch("fill")),
    flops: Integer(fields.fetch("flops")),
    checksum: Integer(fields.fetch("checksum"))
  }
rescue KeyError, ArgumentError => e
  abort "malformed runner output (#{e.message}):\n#{stdout}\n#{stderr}"
end

def median(values)
  sorted = values.sort
  middle = sorted.length / 2
  return sorted[middle] if sorted.length.odd?

  (sorted[middle - 1] + sorted[middle]) / 2.0
end

entries, by_source = corpus_index(options[:corpus])
selected = if options[:gt_10k]
             entries.select { |entry| entry.fetch(:n) > 10_000 }
           else
             requested = options[:cases].empty? ? DEFAULT_SOURCES : options[:cases]
             missing = requested.reject { |source| by_source.key?(source) }
             abort "unknown corpus source(s): #{missing.join(', ')}" unless missing.empty?
             requested.map { |source| by_source.fetch(source) }
           end
abort "selection is empty" if selected.empty?

puts %w[source n nnz offdiag_nnz rounds median_ns min_ns fill flops checksum restarts stream budget].join("\t")

File.open(options[:corpus], "rb") do |corpus_io|
  selected.each do |entry|
    record = read_record(corpus_io, entry)
    Dir.mktmpdir("tungsten-ssi-corpus-") do |dir|
      flat_path = File.join(dir, "pattern.txt")
      offdiag_nnz = write_flat_pattern(record, flat_path)
      samples = []

      options[:rounds].times do |round|
        warn "ssi-corpus #{entry.fetch(:source)} round #{round + 1}/#{options[:rounds]}"
        sample = run_once(
          options[:binary], flat_path, options[:stream], options[:budget], options[:restarts]
        )
        abort "runner n mismatch for #{entry.fetch(:source)}" unless sample[:n] == entry.fetch(:n)
        abort "runner nnz mismatch for #{entry.fetch(:source)}" unless sample[:nnz] == entry.fetch(:nnz)
        samples << sample
      end

      first = samples.first
      structural = first.values_at(:fill, :flops, :checksum, :restarts, :stream, :budget)
      unless samples.all? { |sample| sample.values_at(:fill, :flops, :checksum, :restarts, :stream, :budget) == structural }
        abort "non-deterministic structural result for #{entry.fetch(:source)}"
      end

      puts [
        entry.fetch(:source), entry.fetch(:n), entry.fetch(:nnz), offdiag_nnz,
        samples.length, format("%.1f", median(samples.map { |sample| sample.fetch(:ns) })),
        format("%.1f", samples.map { |sample| sample.fetch(:ns) }.min),
        first.fetch(:fill), first.fetch(:flops), first.fetch(:checksum),
        first.fetch(:restarts), first.fetch(:stream), first.fetch(:budget)
      ].join("\t")
    end
  end
end
