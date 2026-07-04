# Tokenizer smoke: load qwen3 vocab from GGUF, decode a known token
# sequence, encode simple strings, verify decode(encode(s)) == s.

use tungsten-llama/gguf
use tungsten-llama/tokenizer

GGUF_PATH = "/Users/erik/.ollama/models/blobs/sha256-ae354763fe478c790125fb993e59bb1266655b3fa721eebe4a931660c3ed2ce9"

g = GGUF.new(GGUF_PATH)
tok = Tokenizer.new(g)

<< "vocab size: " + tok.tokens.length().to_s
<< "merges: " + tok.merges.length().to_s
<< "bos = " + tok.bos_id.to_s + ", eos = " + tok.eos_id.to_s + ", pad = " + tok.pad_id.to_s

# 1. Decode tokens we already verified by direct lookup.
<< ""
<< "decode tests:"
<< "  [9707] = '" + tok.decode([9707]) + "'"          # "Hello"
<< "  [3838] = '" + tok.decode([3838]) + "'"          # "What"
<< "  [59604] = '" + tok.decode([59604]) + "'"        # "Paris"
<< "  [30] = '" + tok.decode([30]) + "'"              # "?"

# 2. Round-trip simple inputs.
<< ""
<< "round-trip tests:"
inputs = ["Hello world", "What is the capital of France?", "Paris", "The capital is Paris"]
i = 0
while i < inputs.length()
  s = inputs[i]
  ids = tok.encode(s)
  back = tok.decode(ids)
  ok = "OK"
  if back != s
    ok = "MISMATCH"
  << "  \[" + ok + "\] '" + s + "' → " + ids.to_s + " → '" + back + "'"
  i = i + 1

g.close
