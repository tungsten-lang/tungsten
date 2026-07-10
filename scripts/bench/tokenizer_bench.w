# Tungsten-llama tokenizer micro-benchmark — encodes a fixed text
# multiple times to measure bytes/sec and tokens/sec.

use tungsten-llama/gguf
use tungsten-llama/tokenizer

GGUF_PATH = "/Users/erik/.ollama/models/blobs/sha256-ae354763fe478c790125fb993e59bb1266655b3fa721eebe4a931660c3ed2ce9"

g = GGUF.new(GGUF_PATH)
tok = Tokenizer.new(g)
<< "vocab loaded: " + tok.tokens.size().to_s + " tokens, " + tok.merges.size().to_s + " merges"

# Sample text — 5 paragraphs of mixed prose, ~1.5 KB.
TEXT = "The quick brown fox jumps over the lazy dog. Sphinx of black quartz, judge my vow. Pack my box with five dozen liquor jugs. The five boxing wizards jump quickly.\n\nIn programming, the choice of data structure often determines the performance characteristics of an algorithm. A well-chosen hash table can deliver constant-time lookups, while a poorly tuned one degenerates into linear scans through long collision chains.\n\nLanguage models trained on large corpora exhibit emergent behaviors that were not explicitly programmed: they can perform arithmetic, translate between languages, write code, and answer questions about topics they have never seen explicitly during training.\n\nThe history of compilers is a history of trade-offs. Early compilers prioritized correctness over speed; modern ones invest enormous effort in optimization passes that can take longer than the original program would have run interpreted.\n\nDistributed systems are inherently subject to partial failure. Any node may stop responding, any link may drop messages, and clocks across the cluster will not agree. Designs that ignore these realities tend to break in production at the worst possible time."
ROUNDS = 100

byte_count = TEXT.size
<< "input bytes: " + byte_count.to_s
<< "rounds: " + ROUNDS.to_s

# Warmup
i = 0
while i < 5
  ids = tok.encode(TEXT)
  i = i + 1
<< "warmup tokens: " + ids.size().to_s

# Bench
t0 = ccall("__w_clock_ms")
total_tokens = 0
i = 0
while i < ROUNDS
  ids = tok.encode(TEXT)
  total_tokens = total_tokens + ids.size()
  i = i + 1
elapsed = ccall("__w_clock_ms") - t0

total_bytes = byte_count * ROUNDS
mb_per_s = (total_bytes * ~1.0) / (elapsed * ~1.0) / ~1000.0
tokens_per_s = (total_tokens * ~1.0) / (elapsed * ~1.0) * ~1000.0

<< ""
<< "elapsed: " + elapsed.to_s + " ms"
<< "throughput: " + mb_per_s.to_s + " MB/s"
<< "rate: " + tokens_per_s.to_s + " tokens/s"

# Round-trip check
back = tok.decode(ids)
<< "round-trip: " + (back == TEXT ? "OK" : "MISMATCH").to_s

g.close
