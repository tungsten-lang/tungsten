# frozen_string_literal: true

require "prism"

file = ARGV.fetch(0) { abort "usage: ruby bench_prism.rb <file.rb> [rounds]" }
rounds = Integer(ARGV[1] || 20)
source = File.binread(file)
bytes = source.bytesize

def bench(label, rounds, bytes)
  yield
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  result = nil
  rounds.times { result = yield }
  t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  ms = ((t1 - t0) * 1000.0)
  mbps = (bytes * rounds / 1_000_000.0) / (ms / 1000.0)
  [label, ms, mbps, result]
end

puts "Ruby Prism Benchmark"
puts "  file: #{file}"
puts "  bytes: #{bytes}  rounds: #{rounds}"

parse = bench("Prism.parse", rounds, bytes) { Prism.parse(source) }
puts "  #{parse[0]}: #{format('%.3f', parse[1])}ms, #{format('%.1f', parse[2])} MB/s"

lex = bench("Prism.lex", rounds, bytes) { Prism.lex(source) }
tokens = lex[3].value.length
puts "  #{lex[0]}: #{format('%.3f', lex[1])}ms, #{format('%.1f', lex[2])} MB/s, tokens/round: #{tokens}"

