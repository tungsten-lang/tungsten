# Tungsten C Lexer Benchmark
#
# Measures tokenization throughput on real-world C source files.
# Two modes: NaN-boxed (baseline) and machine i64 (optimized).
#
# Usage:
#   tungsten compile benchmarks/c_lexer/bench.w --out bench_lexer
#   ./bench_lexer <file.c> [rounds]

use ../../languages/c/lexer

args = argv()
if args.length() == 0
  << "Tungsten C Lexer Benchmark"
  << ""
  << "Usage: bench_lexer <file.c> [rounds]"
  << ""
  << "Tokenizes a C source file and reports throughput in chars/sec"
  << "and MB/sec. Runs both NaN-boxed baseline and machine i64"
  << "optimized paths for comparison."
  exit(0)

file = args[0]
rounds = 20
if args.length() > 1
  rounds = args[1].to_i()

source = read_file(file)
if source == nil
  << "Error: cannot read [file]"
  exit(1)

lc = source.lchs()
count = lc.length()
byte_count = source.length()

<< "╔══════════════════════════════════════════════════════════╗"
<< "║            Tungsten C Lexer Benchmark                   ║"
<< "╚══════════════════════════════════════════════════════════╝"
<< ""
<< "  File:   [file]"
<< "  Chars:  [count]"
<< "  Bytes:  [byte_count]"
<< "  Rounds: [rounds]"
<< ""

# --- NaN-boxed baseline ---
tokens_baseline = i64[count]
c_tokenize(lc, count, tokens_baseline)

t0 = ccall("__w_clock_ms")
total_baseline = 0 ## i64
r = 0 ## i64
while r < rounds
  total_baseline += c_tokenize(lc, count, tokens_baseline)
  r += 1
t1 = ccall("__w_clock_ms")
ms_baseline = t1 - t0
if ms_baseline == 0
  ms_baseline = 1

# --- Machine i64 optimized ---
tokens_fast = i64[count]
c_tokenize_fast(lc, count, tokens_fast)

t2 = ccall("__w_clock_ms")
total_fast = 0 ## i64
r = 0
while r < rounds
  total_fast += c_tokenize_fast(lc, count, tokens_fast)
  r += 1
t3 = ccall("__w_clock_ms")
ms_fast = t3 - t2
if ms_fast == 0
  ms_fast = 1

baseline_mcs = count * rounds * 1000 / ms_baseline / 1000000
fast_mcs = count * rounds * 1000 / ms_fast / 1000000
baseline_mbs = byte_count * rounds * 1000 / ms_baseline / 1000000
fast_mbs = byte_count * rounds * 1000 / ms_fast / 1000000

<< "  Results:"
<< "  ────────────────────────────────────────────────────────"
<< "  NaN-boxed:   [ms_baseline]ms  [baseline_mcs]M chars/sec  [baseline_mbs] MB/sec  [total_baseline / rounds] tokens"
<< "  Machine i64: [ms_fast]ms  [fast_mcs]M chars/sec  [fast_mbs] MB/sec  [total_fast / rounds] tokens"
<< "  Speedup:     [ms_baseline / ms_fast]x"
<< ""

# --- End-to-end (including lchs() materialization) ---
t4 = ccall("__w_clock_ms")
total_e2e = 0 ## i64
r = 0
while r < rounds
  lc_fresh = source.lchs()
  total_e2e += c_tokenize_fast(lc_fresh, lc_fresh.length(), i64[lc_fresh.length()])
  r += 1
t5 = ccall("__w_clock_ms")
ms_e2e = t5 - t4
if ms_e2e == 0
  ms_e2e = 1
e2e_mbs = byte_count * rounds * 1000 / ms_e2e / 1000000

<< "  End-to-end:  [ms_e2e]ms  [e2e_mbs] MB/sec  (includes lchs() materialization)"
<< ""
<< "  Compare with: cc -O3 benchmarks/c_lexer/bench_c_baseline.c -o /tmp/bench_c && /tmp/bench_c <file>"
<< ""
