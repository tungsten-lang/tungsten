use ./lexer32_twopass

args = argv()
if args.size() == 0
  << "usage: json_twopass <file.json> [rounds]"
  exit(1)

file = args[0]
rounds = 5
if args.size() > 1
  rounds = args[1].to_i()

source = read_file(file)
lc = source.lchs("json", bits: 32)
count = lc.size()
byte_count = source.size()

<< "JSON Lexer Benchmark (Lex32 TWO-PASS — offsets + derive_types)"
<< "  file: [file]"
<< "  chars: [count]  bytes: [byte_count]  rounds: [rounds]"

offsets = i32[count]
types = u8[count]

# Warmup
tc0 = json_tokenize_offsets32(lc, count, offsets)
json_derive_types32(lc, offsets, tc0, types)

t0 = ccall("__w_clock_ms")
total_tokens = 0 ## i64
r = 0 ## i64
while r < rounds
  tc = json_tokenize_offsets32(lc, count, offsets)
  json_derive_types32(lc, offsets, tc, types)
  total_tokens += tc
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
