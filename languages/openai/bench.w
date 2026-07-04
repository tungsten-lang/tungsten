# OpenAI tokenizer benchmark
#
# Usage:
#   tungsten compile languages/openai/bench.w --out tiktoken_bench
#   ./tiktoken_bench <vocab.tiktoken> <text-file> [rounds] [workers] [mode]
#
#   mode: seq (default), go, threaded

use ./tokenizer

args = argv()
if args.size() < 2
  << "usage: tiktoken_bench <vocab.tiktoken> <text-file> [rounds] [workers] [mode]"
  << "  mode: seq (default), go, threaded"
  exit(1)

vocab_path = args[0]
file = args[1]
rounds = 5
if args.size() > 2
  rounds = args[2].to_i()
workers = 0
if args.size() > 3
  workers = args[3].to_i()
mode = "seq"
if args.size() > 4
  mode = args[4]

<< "Loading vocabulary..."
tok = load_tokenizer(vocab_path)
<< "  [tok[:size]] tokens loaded"

# Freeze the string slab — vocab keys are already interned, encode-time
# lookups now go through the lock-free intern table (runtime.c:940-958).
# No slab mutex contention across parallel workers. Intended syntax once
# the BUILTIN token is wired up: Tungsten.STOP_THE_INTERNS!
freeze_slab()

text = read_file(file)
byte_count = text.size()
<< ""
<< "OpenAI Tokenizer Benchmark (o200k_base)"
<< "  file:    [file]"
<< "  bytes:   [byte_count]"
<< "  rounds:  [rounds]"
<< "  workers: [workers]"
<< "  mode:    [mode]"

if (mode == "go" || mode == "shared") && workers > 0
  ccall("w_scheduler_start", workers)

# Warm-up
if mode == "go" && workers > 0
  ids = encode_parallel(tok, text, workers)
elsif mode == "shared" && workers > 0
  ids = encode_parallel_shared(tok, text, workers)
else
  ids = encode(tok, text)
<< "  tokens: [ids.size()]"

# Verify round-trip
decoded = decode(tok, ids)
if decoded == text
  << "  round-trip: OK"
else
  << "  round-trip: MISMATCH (decoded [decoded.size()] bytes vs [byte_count])"

<< ""

# Benchmark
t0 = clock()
i = 0
total_tokens = 0
while i < rounds
  if mode == "go" && workers > 0
    result = encode_parallel(tok, text, workers)
  elsif mode == "shared" && workers > 0
    result = encode_parallel_shared(tok, text, workers)
  else
    result = encode(tok, text)
  total_tokens += result.size()
  i += 1
elapsed = clock() - t0

if (mode == "go" || mode == "shared") && workers > 0
  ccall("w_scheduler_stop")

<< "  time:       [elapsed]ms"
<< "  tokens/sec: [(total_tokens * 1000) / (elapsed + 1)]"
if elapsed > 0
  throughput = (byte_count * rounds * 1000) / (elapsed * 1024 * 1024)
  << "  throughput: [throughput] MB/s"
