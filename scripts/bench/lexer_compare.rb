# frozen_string_literal: true

require "open3"

root = File.expand_path("../..", __dir__)
$LOAD_PATH.unshift(File.join(root, "implementations/ruby/lib"))

require "tungsten"

file = ARGV.fetch(0) do
  warn "usage: ruby scripts/bench/lexer_compare.rb <file.w> [rounds]"
  exit 1
end
rounds = (ARGV[1] || "10").to_i
source = File.read(File.expand_path(file, root))
byte_count = source.bytesize
bench_bin = "/tmp/tungsten-lex-bench"

unless File.executable?(bench_bin)
  ok = system(File.join(root, "bin/tungsten"), "compile", "compiler/bench_lex.w", "--out", bench_bin, chdir: root)
  exit 1 unless ok
end

puts Open3.capture2(bench_bin, file, rounds.to_s, chdir: root).first

def bench_ruby_lexer(name, rounds, byte_count)
  GC.start
  warmup = yield
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
  total = 0
  rounds.times do
    total += yield
  end
  elapsed_ns = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) - t0
  elapsed_ms = [(elapsed_ns / 1_000_000.0).round(1), 0.1].max
  mbps = (byte_count * rounds * 1000.0 / elapsed_ms / 1_000_000).round(1)

  puts "  #{name}: #{elapsed_ms}ms  tokens/round: #{total / rounds}  throughput: #{mbps} MB/s"
  warmup
end

puts
puts "Ruby lexer benchmark"
regex_tokens = bench_ruby_lexer("ruby regex", rounds, byte_count) do
  lexer = Tungsten::Lexer.new(source)
  lexer.file = file
  lexer.tokens.length
end

codepoint_tokens = bench_ruby_lexer("ruby codepoint", rounds, byte_count) do
  lexer = Tungsten::CodepointLexer.new(source)
  lexer.file = file
  lexer.tokens.length
end

puts "  warmup tokens: regex=#{regex_tokens} codepoint=#{codepoint_tokens}"
