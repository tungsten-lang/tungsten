# JSON Lexer single-thread benchmark.
#
# Usage: tungsten compile languages/json/bench.w --out json_bench
#        ./json_bench <file.json> [rounds]

use ./lexer16

args = argv()
if args.size() == 0
  << "usage: json_bench <file.json> [rounds]"
  exit(1)

file = args[0]
rounds = 5
if args.size() > 1
  rounds = args[1].to_i()

source = read_file(file)
lc = source.lchs("json", bits: 16)
count = lc.size()
byte_count = source.size()

<< "JSON Lexer Benchmark (Lex16)"
<< "  file: [file]"
<< "  chars: [count]  bytes: [byte_count]  rounds: [rounds]"

tokens = i32[count]
json_tokenize_fast16(lc, count, tokens)

t0 = ccall("__w_clock_ms")
total_tokens = 0 ## i64
r = 0 ## i64
while r < rounds
  total_tokens += json_tokenize_fast16(lc, count, tokens)
  r += 1
t1 = ccall("__w_clock_ms")

ms = t1 - t0
if ms == 0
  ms = 1
bytes_total = byte_count * rounds
mb_per_sec = bytes_total * 1000 / ms / 1000000

<< ""
<< "  time: [ms]ms"
<< "  tokens/round: [total_tokens / rounds]"
<< "  throughput: [mb_per_sec] MB/s"
