# Token benchmark — C-side raw pointer scan vs Tungsten lexer
#
# w_lexchar_scan_bench does the entire scan loop in C with raw pointer
# access to the typed i64 array. No bounds checks, no boxing.

use ../compiler/lib/lexer

args = argv()
if args.size() == 0
  << "usage: bench_token_cscan.w <file.w> [rounds]"
  exit(1)

file = args[0]
rounds = 20
if args.size() > 1
  rounds = args[1].to_i()

source = read_file(file)
lc = source.lchs()
char_count = source.size()
lc_count = lc.size() ## i64

<< "Token C-scan benchmark"
<< "  file: [file] ([char_count] chars, [rounds] rounds)"

# Warmup
ccall("w_lexchar_scan_bench", lc, lc_count)

# Benchmark: C raw pointer scan (use float clock — sub-ms resolution)
t0 = ccall("__w_clock")
total_c = 0 ## i64
r = 0 ## i64
while r < rounds
  total_c += ccall("w_lexchar_scan_bench", lc, lc_count)
  r += 1
t1 = ccall("__w_clock")
sec_c = t1 - t0

# Benchmark: hash tokens (current lexer)
t2 = ccall("__w_clock")
total_hash = 0 ## i64
r = 0
while r < rounds
  toks = Lexer.new(source, file).tokenize()
  total_hash += toks.size()
  r += 1
t3 = ccall("__w_clock")
sec_hash = t3 - t2

<< ""
<< "  C raw scan:    [sec_c]s  ([total_c / rounds] tokens/lex)"
<< "  hash tokens:   [sec_hash]s  ([total_hash / rounds] tokens/lex)"
<< ""
