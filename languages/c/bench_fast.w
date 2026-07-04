# Benchmark c_tokenize_fast — measures throughput in MB/s

use ./lexer

args = argv()
if args.size() == 0
  << "usage: bench_fast <file.c> [rounds]"
  exit(1)

file = args[0]
rounds = 10
if args.size() > 1
  rounds = args[1].to_i()

source = read_file(file)
lc = source.lchs("c")
count = lc.size()
byte_count = source.size()

<< "C Lexer Benchmark (fast path)"
<< "  file: [file]"
<< "  chars: [count]  bytes: [byte_count]  rounds: [rounds]"

tokens = i64[count]

# Warmup
c_tokenize_fast(lc, count, tokens)

# Benchmark
t0 = ccall("__w_clock_ms")
total_tokens = 0 ## i64
r = 0 ## i64
while r < rounds
  total_tokens += c_tokenize_fast(lc, count, tokens)
  r += 1
t1 = ccall("__w_clock_ms")

ms = t1 - t0
if ms == 0
  ms = 1
bytes_total = byte_count * rounds
bytes_per_sec = bytes_total * 1000 / ms
mb_per_sec = bytes_per_sec / 1000000

<< ""
<< "  time: [ms]ms"
<< "  tokens/round: [total_tokens / rounds]"
<< "  throughput: [mb_per_sec] MB/s"
