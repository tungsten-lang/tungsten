# Concurrent C Lexer Benchmark
#
# Three modes:
# 1. Single-threaded baseline — tokenize file N times sequentially
# 2. Cooperative goroutines — one goroutine per iteration, main thread drives scheduler
# 3. (Future) Multi-threaded — M:P scheduler with worker threads
#
# Measures scaling characteristics of goroutine-based concurrent lexing.

use ../../languages/c/lexer

# --- Single-threaded baseline ---
fn bench_single(lc, count, rounds)
  tokens = i64[count]
  total_tokens = 0 ## i64

  t0 = ccall("__w_clock_ms")
  r = 0 ## i64
  while r < rounds
    total_tokens += c_tokenize(lc, count, tokens)
    r += 1
  t1 = ccall("__w_clock_ms")

  ms = t1 - t0
  if ms == 0
    ms = 1
  chars_per_sec = count * rounds * 1000 / ms
  << "  Single-thread:  [ms]ms  [chars_per_sec / 1000000]M chars/sec  ([total_tokens / rounds] tokens/round)"

# --- Cooperative goroutines ---
# Spawns `goroutines` goroutines, each lexing the file once.
# Main thread collects results via channel.
fn bench_cooperative(lc, count, goroutines)
  ch = Channel.new(goroutines)

  t0 = ccall("__w_clock_ms")
  g = 0
  while g < goroutines
    go ->
      tokens = i64[count]
      n = c_tokenize(lc, count, tokens)
      ch.send(n)
    g += 1

  # Collect results
  total_tokens = 0
  g = 0
  while g < goroutines
    total_tokens += ch.recv()
    g += 1
  t1 = ccall("__w_clock_ms")

  ms = t1 - t0
  if ms == 0
    ms = 1
  chars_per_sec = count * goroutines * 1000 / ms
  << "  Cooperative:    [ms]ms  [chars_per_sec / 1000000]M chars/sec  ([goroutines] goroutines, [total_tokens / goroutines] tokens/round)"

# --- Main ---
args = argv()
if args.size() == 0
  << "usage: bench.w <file.c> [rounds]"
  exit(1)

file = args[0]
rounds = 20
if args.size() > 1
  rounds = args[1].to_i()

source = read_file(file)
lc = source.lchs()
count = lc.size()
byte_count = source.size()

<< "Concurrent C Lexer Benchmark"
<< "  file: [file]"
<< "  chars: [count]"
<< "  bytes: [byte_count]"
<< "  rounds: [rounds]"
<< ""

# Warmup
tokens = i64[count]
c_tokenize(lc, count, tokens)

<< "Results:"
bench_single(lc, count, rounds)
bench_cooperative(lc, count, rounds)
