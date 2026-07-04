# qwen3.6/35b-a3b-nvfp4 load smoke test.
#
# Opens the 4-shard MLX safetensors snapshot, validates that key
# tensors are present + have expected shapes, prints the inventory.
# No inference — just proves we can read the model.
#
# Path forward: once forward.w exists, this becomes the prefill +
# verify_paris-equivalent for qwen3.6.

use core/metal
use tungsten-llama/sharded_safetensors

QWEN36_PATH = "/Users/erik/.cache/huggingface/hub/models--mlx-community--Qwen3.6-35B-A3B-nvfp4/snapshots/9c1a3a223ddd8a3425212cc421056614f149cf0f/model.safetensors.index.json"

<< "loading qwen3.6/35b-a3b-nvfp4 sharded safetensors..."
st = ShardedSafetensors.new(QWEN36_PATH)
<< "  total tensors: " + st.count().to_s

# Spot-check key shapes against config.w expectations.
expected = [
  ["language_model.model.embed_tokens.weight", "248320 × 2048 nvfp4 (vocab × hidden)"],
  ["language_model.model.embed_tokens.scales", "248320 × 128 fp8 scales (vocab × hidden/16)"],
  ["language_model.lm_head.weight",            "248320 × 2048 nvfp4 (untied lm_head)"],
  ["language_model.model.norm.weight",         "2048 bf16 (final RMSNorm γ)"],
  ["language_model.model.layers.0.input_layernorm.weight",     "2048 bf16 (layer 0 = linear_attn)"],
  ["language_model.model.layers.0.linear_attn.A_log",          "32 bf16 (Mamba SSM A param)"],
  ["language_model.model.layers.0.linear_attn.conv1d.weight",  "8192×4×1 bf16 (1D conv kernel)"],
  ["language_model.model.layers.0.linear_attn.dt_bias",        "32 bf16 (Mamba dt bias)"],
  ["language_model.model.layers.0.linear_attn.in_proj_qkv.weight",  "8192×2048 nvfp4 (16+16+32 heads × 128)"],
  ["language_model.model.layers.0.linear_attn.in_proj_z.weight",    "4096×2048 nvfp4 (gate Z)"],
  ["language_model.model.layers.0.linear_attn.out_proj.weight",     "2048×4096 nvfp4 (Mamba out)"],
  ["language_model.model.layers.3.input_layernorm.weight",     "2048 bf16 (layer 3 = full_attn — every 4th)"],
  ["language_model.model.layers.3.self_attn.q_proj.weight",    "8192×2048 nvfp4 (16 heads × 256 head_dim × 2 — output gate)"],
  ["language_model.model.layers.3.self_attn.k_proj.weight",    "512×2048 nvfp4 (2 KV heads × 256, extreme GQA group=8)"],
  ["language_model.model.layers.3.self_attn.v_proj.weight",    "512×2048 nvfp4"],
  ["language_model.model.layers.3.self_attn.o_proj.weight",    "2048×4096 nvfp4 (4096 = 16×256 attn-out)"],
  ["language_model.model.layers.3.self_attn.q_norm.weight",    "256 bf16 (per-head Q norm)"],
  ["language_model.model.layers.3.self_attn.k_norm.weight",    "256 bf16"],
  ["language_model.model.layers.3.mlp.gate.weight",            "256×4096 ??? (router — anomalous quant format)"],
  ["language_model.model.layers.3.mlp.shared_expert.gate_proj.weight", "512×2048 nvfp4 (FFN_dim × HIDDEN)"],
  ["language_model.model.layers.3.mlp.switch_mlp.gate_proj.weight",    "256×512×2048 nvfp4 (256 routed experts)"],
  ["language_model.model.layers.3.mlp.shared_expert_gate.weight",      "1×4096 ??? (scalar gate weight, anomalous)"]
]

<< ""
<< "=== shape inventory ==="
i = 0
all_present = true
while i < expected.size()
  name = expected[i][0]
  desc = expected[i][1]
  if st.has?(name)
    t = st.tensor(name)
    shape_str = ""
    si = 0
    while si < t[:shape].size()
      if si > 0
        shape_str = shape_str + "×"
      shape_str = shape_str + t[:shape][si].to_s
      si = si + 1
    << "  ✓ " + name
    << "      shape=" + shape_str + " dtype=" + t[:dtype] + " — " + desc
  else
    << "  ✗ MISSING: " + name + " — " + desc
    all_present = false
  i = i + 1

<< ""
if all_present
  << "all " + expected.size().to_s + " sentinel tensors present"
else
  << "MISSING tensors above — investigate before porting"

# Layer-type discovery: check which layers have linear_attn vs self_attn.
<< ""
<< "=== layer-type map (40 layers; expect 30 linear_attn + 10 full_attention every 4th) ==="
li = 0
linear_count = 0
full_count = 0
while li < 40
  lattn_key = "language_model.model.layers." + li.to_s + ".linear_attn.A_log"
  full_key  = "language_model.model.layers." + li.to_s + ".self_attn.q_proj.weight"
  ltype = "?"
  if st.has?(lattn_key)
    ltype = "linear_attention"
    linear_count = linear_count + 1
  elsif st.has?(full_key)
    ltype = "full_attention"
    full_count = full_count + 1
  << "  layer " + li.to_s + ": " + ltype
  li = li + 1
<< ""
<< "  totals: " + linear_count.to_s + " linear_attn + " + full_count.to_s + " full_attention"

st.close
<< ""
<< "smoke test passed."
