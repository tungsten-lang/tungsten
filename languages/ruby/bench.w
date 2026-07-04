# Ruby Lex64 lexer benchmark.
#
# Usage: bin/tungsten languages/ruby/bench.w <file.rb> [rounds]

use ./lexer

args = argv()
if args.size() == 0
  << "usage: ruby_lex64_bench <file.rb> [rounds]"
  exit(1)

file = args[0]
rounds = 20
if args.size() > 1
  rounds = args[1].to_i()

source = read_file(file)
lc = source.lchs("ruby")
count = lc.size()
byte_count = source.size()
tokens = i64[count]

ruby_tokenize_fast64(lc, count, tokens)

t0 = ccall("__w_clock_ms")
total_tokens = 0 ## i64
r = 0 ## i64
while r < rounds
  total_tokens += ruby_tokenize_fast64(lc, count, tokens)
  r++
t1 = ccall("__w_clock_ms")

ms = t1 - t0
if ms == 0
  ms = 1

bytes_total = byte_count * rounds
mb_per_sec = bytes_total * 1000 / ms / 1000000

<< "Ruby Lexer Benchmark (Lex64)"
<< "  file: [file]"
<< "  chars: [count]  bytes: [byte_count]  rounds: [rounds]"
<< "  time: [ms]ms"
<< "  tokens/round: [total_tokens / rounds]"
<< "  throughput: [mb_per_sec] MB/s"

