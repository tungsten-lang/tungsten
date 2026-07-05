# JSON Parallel Lexer Benchmark (Lex64 eatws_pure variant)

use ../../languages/json/lexer_eatws_pure

args = argv()
if args.length() == 0
  << "usage: json_par64_pure <file.json> [total_jobs] [goroutines]"
  exit(1)

file = args[0]
total_jobs = 32
if args.length() > 1
  total_jobs = args[1].to_i()
goroutines = 8
if args.length() > 2
  goroutines = args[2].to_i()

source = read_file(file)
lc = source.lchs("json", bits: 64)
count = lc.length()
byte_count = source.length()

<< "JSON Parallel Lexer Benchmark (Lex64 eatws_pure)"
<< "  file:       [file]"
<< "  bytes:      [byte_count]"
<< "  jobs:       [total_jobs]"
<< "  goroutines: [goroutines]"

cells_st = i32[count]
num_tokens = json_tokenize_fast_eatws_pure(lc, count, cells_st)

t0 = ccall("__w_clock_ms")
total_st = 0 ## i64
r = 0 ## i64
while r < total_jobs
  total_st += json_tokenize_fast_eatws_pure(lc, count, cells_st)
  r += 1
t1 = ccall("__w_clock_ms")
ms_st = t1 - t0
if ms_st == 0
  ms_st = 1

ccall("w_scheduler_start", goroutines)
results = Channel.new(total_jobs)

t2 = ccall("__w_clock_ms")
i = 0
while i < total_jobs
  go ->
    cells_local = i32[count]
    n = json_tokenize_fast_eatws_pure(lc, count, cells_local)
    results.send(n)
  i += 1

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
