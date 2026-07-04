# C Lexer Benchmark — measure chars/sec on a C file

use ./lexer

args = argv()
if args.size() == 0
  << "usage: bench.w <file.c> [rounds]"
  exit(1)

file = args[0]
rounds = 10
if args.size() > 1
  rounds = args[1].to_i()

source = read_file(file)
lc = source.lchs()
count = lc.size()
byte_count = source.size()

<< "C Lexer Benchmark"
<< "  file: [file]"
<< "  chars: [count]"
<< "  bytes: [byte_count]"
<< "  rounds: [rounds]"
<< ""

# Pre-allocate token buffer (worst case: 1 token per char)
tokens = i64[count]

# Warmup
c_tokenize(lc, count, tokens)

# Benchmark
t0 = ccall("__w_clock_ms")
total_tokens = 0 ## i64
r = 0 ## i64
while r < rounds
  total_tokens += c_tokenize(lc, count, tokens)
  r += 1
t1 = ccall("__w_clock_ms")

ms = t1 - t0
if ms == 0
  ms = 1
chars_total = count * rounds
bytes_total = byte_count * rounds
chars_per_sec = chars_total * 1000 / ms
bytes_per_sec = bytes_total * 1000 / ms

<< "Results:"
<< "  time: [ms]ms"
<< "  tokens/round: [total_tokens / rounds]"
<< "  [chars_per_sec / 1000000]M chars/sec"
<< "  [bytes_per_sec / 1000000]M bytes/sec"
