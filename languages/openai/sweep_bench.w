use ./tokenizer

<< "Loading vocabulary..."
tok = load_tokenizer("languages/openai/o200k_base.tiktoken")
<< "  [tok[:size]] tokens loaded"
freeze_slab()

text = read_file("/tmp/huge.c")
byte_count = text.size()
<< "bytes=[byte_count]"

# Start scheduler with max workers we'll need
ccall("w_scheduler_start", 16)

# Warm-up
ids = encode(tok, text)
<< "warmup tokens=[ids.size()]"

rounds = 5

# Sequential baseline
t0 = clock()
r = 0
while r < rounds
  result = encode(tok, text)
  r += 1
elapsed = clock() - t0
tput = (byte_count * rounds * 1000) / (elapsed * 1024 * 1024)
<< "workers= 1 (seq)  throughput: [tput] MB/s"

# Sweep
w = 2
while w <= 15
  t0 = clock()
  r = 0
  while r < rounds
    result = encode_parallel(tok, text, w)
    r += 1
  elapsed = clock() - t0
  tput = (byte_count * rounds * 1000) / (elapsed * 1024 * 1024)
  << "workers=[w]  throughput: [tput] MB/s"
  w += 1

ccall("w_scheduler_stop")
