# P5.1 smoke: load qwen3:30b-a3b-q8_0 GGUF, verify metadata + tensor
# count + a few tensor shapes match what we documented in
# docs/qwen3-moe-shapes.md.

use lib/gguf

GGUF_PATH = "/Users/erik/.ollama/models/blobs/sha256-ae354763fe478c790125fb993e59bb1266655b3fa721eebe4a931660c3ed2ce9"

g = GGUF.new(GGUF_PATH)

# Header sanity
if g.version != 3
  << "FAIL version: " + g.version.to_s
  exit 1
if g.tensors.size() != 579
  << "FAIL tensor_count: " + g.tensors.size().to_s + " (expected 579)"
  exit 1

# Metadata sanity — qwen3moe architecture, expected dims.
arch = g.metadata["general.architecture"]
if arch != "qwen3moe"
  << "FAIL arch: " + arch
  exit 1
if g.metadata["qwen3moe.block_count"] != 48
  << "FAIL block_count"
  exit 1
if g.metadata["qwen3moe.embedding_length"] != 2048
  << "FAIL embedding_length"
  exit 1
if g.metadata["qwen3moe.expert_count"] != 128
  << "FAIL expert_count"
  exit 1

# Spot-check a few tensors against docs/qwen3-moe-shapes.md.
checks = [
  {name: "token_embd.weight",        type: "Q8_0", dims: [2048, 151936]},
  {name: "output.weight",            type: "Q8_0", dims: [2048, 151936]},
  {name: "blk.0.attn_q.weight",      type: "Q8_0", dims: [2048, 4096]},
  {name: "blk.0.attn_k.weight",      type: "Q8_0", dims: [2048, 512]},
  {name: "blk.0.attn_v.weight",      type: "F16",  dims: [2048, 512]},
  {name: "blk.0.attn_output.weight", type: "Q8_0", dims: [4096, 2048]},
  {name: "blk.0.ffn_gate_exps.weight", type: "Q8_0", dims: [2048, 768, 128]},
  {name: "blk.0.ffn_down_exps.weight", type: "Q8_0", dims: [768, 2048, 128]},
  {name: "blk.0.ffn_up_exps.weight",   type: "Q8_0", dims: [2048, 768, 128]},
  {name: "blk.47.ffn_norm.weight",   type: "F32",  dims: [2048]}
]

i = 0
while i < checks.size()
  c = checks[i]
  t = g.tensor(c[:name])
  if t == nil
    << "FAIL missing: " + c[:name]
    exit 1
  if t[:type_name] != c[:type]
    << "FAIL type for " + c[:name] + ": got " + t[:type_name] + " expected " + c[:type]
    exit 1
  if t[:shape].size() != c[:dims].size()
    << "FAIL shape rank for " + c[:name]
    exit 1
  d = 0
  while d < c[:dims].size()
    if t[:shape][d] != c[:dims][d]
      << "FAIL shape for " + c[:name]
      exit 1
    d = d + 1
  i = i + 1

# Sanity-check the data offset: should point past the metadata,
# and total tensor bytes should add up to roughly 30 GB.
total_bytes = 0
i = 0
while i < g.tensors.size()
  total_bytes = total_bytes + g.tensor_bytes(g.tensors[i])
  i = i + 1
total_gb = total_bytes.to_f / ~1024.0 / ~1024.0 / ~1024.0

<< "qwen3 GGUF loaded:"
<< "  version          " + g.version.to_s
<< "  tensors          " + g.tensors.size().to_s
<< "  metadata KVs     " + g.metadata.keys().size().to_s
<< "  data_offset      " + g.data_offset.to_s
<< "  total weight GB  " + total_gb.to_s
<< "  ALL CHECKS PASSED"

g.close
