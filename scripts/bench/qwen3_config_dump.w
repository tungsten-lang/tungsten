# Dump qwen3 config keys we need for P5.4+: rms_norm_eps, rope.freq_base,
# rope.dimension_count, attention head counts.

use tungsten-llama/gguf

GGUF_PATH = "/Users/erik/.ollama/models/blobs/sha256-ae354763fe478c790125fb993e59bb1266655b3fa721eebe4a931660c3ed2ce9"

g = GGUF.new(GGUF_PATH)

keys = [
  "general.architecture",
  "qwen3moe.embedding_length",
  "qwen3moe.block_count",
  "qwen3moe.attention.head_count",
  "qwen3moe.attention.head_count_kv",
  "qwen3moe.attention.layer_norm_rms_epsilon",
  "qwen3moe.attention.key_length",
  "qwen3moe.attention.value_length",
  "qwen3moe.rope.freq_base",
  "qwen3moe.rope.dimension_count",
  "qwen3moe.feed_forward_length",
  "qwen3moe.expert_count",
  "qwen3moe.expert_used_count",
  "qwen3moe.expert_feed_forward_length",
  "qwen3moe.vocab_size"
]

i = 0
while i < keys.size()
  k = keys[i]
  v = g.metadata[k]
  if v == nil
    << k + " = (missing)"
  else
    << k + " = " + v.to_s
  i = i + 1

g.close
