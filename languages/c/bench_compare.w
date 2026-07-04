# C Lexer Benchmark — compare bounds-checked vs raw pointer

use ./lexer

args = argv()
if args.size() == 0
  << "usage: bench_compare.w <file.c> [rounds]"
  exit(1)

file = args[0]
rounds = 10
if args.size() > 1
  rounds = args[1].to_i()

source = read_file(file)
lc = source.lchs()
count = lc.size()
byte_count = source.size()

<< "C Lexer Comparison Benchmark"
<< "  file: [file]"
<< "  chars: [count]  bytes: [byte_count]  rounds: [rounds]"
<< ""

# --- Bounds-checked (original) ---
tokens = i64[count]
c_tokenize(lc, count, tokens)

t0 = ccall("__w_clock_ms")
total_checked = 0 ## i64
r = 0 ## i64
while r < rounds
  total_checked += c_tokenize(lc, count, tokens)
  r += 1
t1 = ccall("__w_clock_ms")
ms_checked = t1 - t0
if ms_checked == 0
  ms_checked = 1

# --- Machine i64 (fast) ---
c_tokenize_fast(lc, count, tokens)

t2 = ccall("__w_clock_ms")
total_fast = 0 ## i64
r = 0
while r < rounds
  total_fast += c_tokenize_fast(lc, count, tokens)
  r += 1
t3 = ccall("__w_clock_ms")
ms_fast = t3 - t2
if ms_fast == 0
  ms_fast = 1

checked_mcs = count * rounds * 1000 / ms_checked / 1000000
fast_mcs = count * rounds * 1000 / ms_fast / 1000000
checked_mbs = byte_count * rounds * 1000 / ms_checked / 1000000
fast_mbs = byte_count * rounds * 1000 / ms_fast / 1000000

<< "  Bounds-checked: [ms_checked]ms  [checked_mcs]M chars/sec  [checked_mbs]M bytes/sec  ([total_checked / rounds] tokens)"
<< "  Raw pointer:    [ms_fast]ms  [fast_mcs]M chars/sec  [fast_mbs]M bytes/sec  ([total_fast / rounds] tokens)"
if ms_fast < ms_checked
  << "  Speedup: [ms_checked / ms_fast]x"
else
  << "  No speedup (raw pointer slower)"
