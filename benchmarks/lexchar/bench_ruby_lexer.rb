#!/usr/bin/env ruby
# LexChar benchmark — Ruby lexer throughput
#
# Measures chars/sec and tokens/sec for the Ruby lexer on real source files.

require_relative "../../implementations/ruby/lib/tungsten"

files = ARGV.empty? ? Dir["../../compiler/lib/*.w"] : ARGV
sources = files.map { |f| [f, File.read(f)] }

total_chars = sources.sum { |_, s| s.length }
total_lines = sources.sum { |_, s| s.count("\n") }
puts "LexChar — Ruby lexer benchmark"
puts "  #{sources.length} files, #{total_chars} chars, #{total_lines} lines"
puts ""

# Warmup
3.times { sources.each { |_, src| Tungsten::Lexer.new(src).tokens } }

# Benchmark
rounds = 10
t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
total_tokens = 0
rounds.times do
  sources.each do |_, src|
    tokens = Tungsten::Lexer.new(src).tokens
    total_tokens += tokens.length
  end
end
dt = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0

chars_per_sec = (total_chars * rounds) / dt
tokens_per_sec = total_tokens / dt
ms_per_file = (dt / (sources.length * rounds)) * 1000

puts "  #{rounds} rounds in #{"%.2f" % dt}s"
puts "  #{"%.1f" % (chars_per_sec / 1e6)}M chars/sec"
puts "  #{"%.1f" % (tokens_per_sec / 1e6)}M tokens/sec"
puts "  #{"%.2f" % ms_per_file}ms per file (avg)"
puts ""

# Per-file breakdown (single pass)
puts "  Per-file breakdown:"
sources.sort_by { |_, s| -s.length }.first(5).each do |path, src|
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  50.times { Tungsten::Lexer.new(src).tokens }
  dt = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
  name = File.basename(path)
  mchars = (src.length * 50) / dt / 1e6
  puts "    #{name.ljust(20)} #{src.length.to_s.rjust(6)} chars  #{"%.1f" % mchars}M chars/sec"
end
