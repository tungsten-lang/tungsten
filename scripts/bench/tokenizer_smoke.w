# Tokenizer smoke: load the packed Qwen tokenizer, decode known tokens,
# encode simple strings, and verify decode(encode(s)) == s.

use tungsten-llama/tokenizer

TOKENIZER_BIN = "/Users/erik/.cache/tungsten/qwen3.8-27b-mlx/tokenizer.json.bin"

tok = Tungsten:Llama:Tokenizer.from_packed_tokenizer(TOKENIZER_BIN)

<< "vocab size: " + tok.tokens.size().to_s
<< "merges: " + tok.merges.size().to_s
<< "bos = " + tok.bos_id.to_s + ", eos = " + tok.eos_id.to_s + ", pad = " + tok.pad_id.to_s

# 1. Decode tokens we already verified by direct lookup.
<< ""
<< "decode tests:"
<< "  [9419] = '" + tok.decode([9419]) + "'"          # "Hello"
<< "  [3710] = '" + tok.decode([3710]) + "'"          # "What"
<< "  [57590] = '" + tok.decode([57590]) + "'"        # "Paris"
<< "  [30] = '" + tok.decode([30]) + "'"              # "?"

# 2. Round-trip simple inputs.
<< ""
<< "round-trip tests:"
inputs = ["Hello world", "What is the capital of France?", "Paris", "The capital is Paris"]
i = 0
while i < inputs.size()
  s = inputs[i]
  ids = tok.encode(s)
  back = tok.decode(ids)
  ok = "OK"
  if back != s
    ok = "MISMATCH"
  << "  \[" + ok + "\] '" + s + "' → " + ids.to_s + " → '" + back + "'"
  i = i + 1
