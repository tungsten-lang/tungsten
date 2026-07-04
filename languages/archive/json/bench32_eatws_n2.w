use ./lexer32_eatws_n2

args = argv()
if args.size() == 0
  << "usage: json_offs <file.json> [rounds]"
  exit(1)

file = args[0]
rounds = 5
if args.size() > 1
  rounds = args[1].to_i()

source = read_file(file)
lc = source.lchs("json", bits: 32)
count = lc.size()
byte_count = source.size()

<< "JSON Lexer Benchmark (Lex32 EAT-WS — inline trailing-ws eat in each emit branch)"
<< "  file: [file]"
<< "  chars: [count]  bytes: [byte_count]  rounds: [rounds]"

offsets = i32[count]
json_tokenize_fast32_eatws_n2(lc, count, offsets)

t0 = ccall("__w_clock_ms")
total_tokens = 0 ## i64
r = 0 ## i64
while r < rounds
  total_tokens += json_tokenize_fast32_eatws_n2(lc, count, offsets)
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
