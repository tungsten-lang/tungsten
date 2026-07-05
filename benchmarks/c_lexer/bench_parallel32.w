# Parallel C Lexer Benchmark
#
# Tokenizes a file N times using goroutines pulling from a work queue.
# Each goroutine: dequeue index → tokenize full file → send result via channel.
#
# Usage:
#   tungsten compile benchmarks/c_lexer/bench_parallel.w --out bench_parallel
#   ./bench_parallel <file.c> [total_jobs] [goroutines]

use ../../languages/c/lexer32

args = argv()
if args.length() == 0
  << "Usage: bench_parallel <file.c> [total_jobs] [goroutines]"
  exit(1)

file = args[0]
total_jobs = 20
if args.length() > 1
  total_jobs = args[1].to_i()
goroutines = 8
if args.length() > 2
  goroutines = args[2].to_i()

source = read_file(file)
lc = source.lchs("c", bits: 32)             # C-specific codepoints: IS_ID_START includes A-Z
count = lc.length()
byte_count = source.length()

<< "Parallel C Lexer Benchmark (Lex32)"
<< "  file:       [file]"
<< "  chars:      [count]"
<< "  bytes:      [byte_count]"
<< "  jobs:       [total_jobs]"
<< "  goroutines: [goroutines]"
<< ""

# --- Single-threaded baseline ---
tokens_st = i64[count]
num_tokens = c_tokenize_fast32(lc, count, tokens_st)

t0 = ccall("__w_clock_ms")
total_st = 0 ## i64
r = 0 ## i64
while r < total_jobs
  total_st += c_tokenize_fast32(lc, count, tokens_st)
  r += 1
t1 = ccall("__w_clock_ms")
ms_st = t1 - t0
if ms_st == 0
  ms_st = 1

# --- M:P parallel goroutines (true multi-threaded) ---
ccall("w_scheduler_start", goroutines)
results = Channel.new(total_jobs)

t2 = ccall("__w_clock_ms")
i = 0
while i < total_jobs
  go ->
    tokens_local = i64[count]
    n = c_tokenize_fast32(lc, count, tokens_local)
    results.send(n)
  i += 1

# Collect results
total_par = 0
i = 0
while i < total_jobs
  total_par += results.recv()
  i += 1
t3 = ccall("__w_clock_ms")
ccall("w_scheduler_stop")
ms_par = t3 - t2
if ms_par == 0
  ms_par = 1

st_mbs = byte_count * total_jobs * 1000 / ms_st / 1000000
par_mbs = byte_count * total_jobs * 1000 / ms_par / 1000000

<< "  Single-thread: [ms_st]ms  [st_mbs] MB/sec  [total_st / total_jobs] tokens/job"
<< "  Parallel:      [ms_par]ms  [par_mbs] MB/sec  [total_par / total_jobs] tokens/job"
if ms_par < ms_st
  << "  Speedup:       [ms_st / ms_par]x"
else
  << "  No speedup"
