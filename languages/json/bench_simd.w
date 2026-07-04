# JSON SIMD lexer single-thread benchmark.
#
# Usage: tungsten compile languages/json/bench_simd.w --out json_simd
#        ./json_simd <file.json> [rounds]

use ./lexer_simd

args = argv()
if args.size() == 0
  << "usage: json_simd <file.json> [rounds]"
  exit(1)

file = args[0]
rounds = 5
if args.size() > 1
  rounds = args[1].to_i()

source = read_file(file)
byte_count = source.size()

<< "JSON SIMD Lexer Benchmark"
<< "  file: [file]"
<< "  bytes: [byte_count]  rounds: [rounds]"

tokens = i32[byte_count]
json_tokenize_simd(source, tokens)

t0 = ccall("__w_clock_ms")
total_tokens = 0 ## i64
r = 0 ## i64
while r < rounds
  total_tokens += json_tokenize_simd(source, tokens)
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
