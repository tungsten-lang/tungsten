# Decode-only Qwen3.8-Flash-Next (qwen4_exp) NVFP4 inference on Metal.
#
# 125B/A6B MoE previewing the Qwen4 architecture: 3:1 GatedDeltaNet : full
# attention, 512-expert top-10 MoE per layer, 4-branch hyper-connection
# residual stream (10240 f32), n-gram PLE injection at decoder layer 1,
# QSA sparse attention (dense-exact below 2051 tokens, which MAX_POS
# guarantees, so the indexer is skipped entirely).
#
# Prepare (after `hf download RadixArk/Qwen3.8-Flash-Next-NVFP4`):
#   python3 scripts/bench/prepare_flash_next.py
#   python3 bits/tungsten-llama/scripts/tokenizer_pack.py \
#     ~/.cache/tungsten/qwen38-flash-next-nvfp4/tokenizer.json \
#     ~/.cache/tungsten/qwen38-flash-next-nvfp4/tokenizer.json.bin
#
# Run:
#   bin/tungsten run scripts/bench/qwen38fn_mlx.w concurrent 8
#   bin/tungsten run scripts/bench/qwen38fn_mlx.w baseline 8 5
#
# ARGV: [0] mode = baseline|concurrent   [1] tokens to generate
#       [2] prompt token count (default 5 = parity fixture)
#       [3] JSON file of prompt token ids (overrides [2])
#       [4] golden prefix: dump per-layer H + logits for the LAST prompt
#           position to <prefix>_{h,logits,dbg}.f32
#       [5] "expert-hist" (dump routing histogram) | "pin:<N>" (wire the
#           per-layer top-N experts from /tmp/fn_expert_hist.u32)

use core/metal
use core/json
use tungsten-llama/sharded_safetensors
use tungsten-llama/tokenizer

MODEL_DIR = "/Users/erik/.cache/tungsten/qwen38-flash-next-nvfp4/"
MODEL_INDEX = MODEL_DIR + "index.slim.json"
EXPERTS_MANIFEST = MODEL_DIR + "experts_manifest.json"
PLE_MANIFEST = MODEL_DIR + "ple_manifest.json"
TOKENIZER_BIN = MODEL_DIR + "tokenizer.json.bin"
NVFP4_DIR = "bits/tungsten-llama/lib/kernels/nvfp4/"
SHARED_DIR = "bits/tungsten-llama/lib/kernels/shared/"
QWEN_DIR = "bits/tungsten-llama/lib/kernels/qwen3_6/"
FN_DIR = "bits/tungsten-llama/lib/kernels/qwen4_fn/"

HIDDEN = 2560
N_LAYERS = 48
N_VOCAB = 248320
EPS = ~0.000001
HC_COUNT = 4
HC_HIDDEN = HC_COUNT * HIDDEN
HC_LOWRANK = 320

# Linear attention / GatedDeltaNet (identical geometry to qwen3.8-27b).
HK = 16
HV = 48
DK = 128
DV = 128
Q_DIM = HK * DK
K_DIM = HK * DK
V_DIM = HV * DV
QKV_DIM = Q_DIM + K_DIM + V_DIM

# Full attention.
N_HEADS = 24
N_KV_HEADS = 2
HEAD_DIM = 256
GQA = N_HEADS / N_KV_HEADS
KV_DIM = N_KV_HEADS * HEAD_DIM
ATTN_DIM = N_HEADS * HEAD_DIM
QFULL_DIM = ATTN_DIM * 2
ATTN_SCALE = ~1.0 / Math.sqrt(~0.0 + HEAD_DIM)
ROT_DIM = 64
ROT_HALF = ROT_DIM / 2
ROPE_BASE = ~10000000.0
MAX_POS = 640

# MoE.
N_EXPERTS = 512
TOP_K = 10
MOE_FFN = 640
SHARED_FFN = 640

# PLE.
PLE_LAYER = 1
PLE_STATE = 9
EOS_TOKEN = 248044
ARGMAX_CHUNKS = (N_VOCAB + 1023) / 1024

mode = ARGV.size() > 0 ? ARGV[0] : "concurrent"
n_generate = ARGV.size() > 1 ? ARGV[1].to_i() : 8
prompt_tokens = ARGV.size() > 2 ? ARGV[2].to_i() : 5
prompt_ids_file = ARGV.size() > 3 ? ARGV[3] : ""
golden_prefix = ARGV.size() > 4 ? ARGV[4] : ""
expert_hist = ARGV.size() > 5 && ARGV[5] == "expert-hist"
# "pin:<N>" wires the per-layer top-N experts (by /tmp/fn_expert_hist.u32 from
# an expert-hist run) into a private hot overlay the gather kernel prefers.
pin_count = 0
if ARGV.size() > 5 && ARGV[5].size() > 4 && ARGV[5].slice(0, 4) == "pin:"
  pin_count = ARGV[5].slice(4, ARGV[5].size() - 4).to_i()
if pin_count > 512 then raise "pin count must be <= 512"
concurrent = mode == "concurrent"
if mode != "concurrent" && mode != "baseline"
  raise "usage: qwen38fn_mlx.w [baseline|concurrent] [tokens] [prompt_tokens] [prompt_ids.json] [golden_prefix]"
if prompt_tokens + n_generate > MAX_POS
  raise "prompt " + prompt_tokens.to_s + " + generate " + n_generate.to_s + " exceeds MAX_POS " + MAX_POS.to_s + "; the K/V cache would wrap and the run would report plausible numbers for garbage output"

setup_t0 = ccall("__w_clock_ms")
device = metal_device()
queue = metal_queue(device)
st = Tungsten:Llama:ShardedSafetensors.new(MODEL_INDEX)
experts_man = JSON.parse(read_file(EXPERTS_MANIFEST))
ple_man = JSON.parse(read_file(PLE_MANIFEST))
# FN_QUANT=1: route the big matvecs through self-quantized NVFP4 sidecars
# (quantize_flash_next.py; layers 0/1/46/47 stay bf16 there and fall through).
selfquant = ccall("__w_env", "FN_QUANT") == "1"
# FN_SKIP=moe,gdn,attn,hc,head,shared,ple: ablation profiling — skip whole
# stages to price them (outputs become garbage; ONLY the timing is valid).
skip_spec = ccall("__w_env", "FN_SKIP")
if skip_spec == nil then skip_spec = ""
skip_moe = skip_spec.include?("moe")
skip_gdn = skip_spec.include?("gdn")
skip_attn = skip_spec.include?("attn")
skip_hc = skip_spec.include?("hc")
skip_head = skip_spec.include?("head")
skip_shared = skip_spec.include?("shared")
skip_ple = skip_spec.include?("ple")
if skip_spec != "" then << "ABLATION: skipping " + skip_spec + " — output is garbage, timing only"
# FN_HCFUSED=1: 2-stage fused HC mix. Measured 2ms SLOWER than the 5-stage
# path (the concurrent encoder already overlaps those stages) — kept only
# so the negative result stays reproducible.
hc_fused = ccall("__w_env", "FN_HCFUSED") == "1"
# Pipelined encode: commit the token's command buffer in thirds so encoding
# layers 17-48 overlaps GPU execution of layers 1-16 (the flame profile
# priced host encode at ~6.5ms/token, fully serial with the GPU when the
# token is a single buffer). Queue order serializes the pieces.
sq = nil
if selfquant
  sq = Tungsten:Llama:Safetensors.new(MODEL_DIR + "selfquant.safetensors")
  << "selfquant: " + sq.count().to_s + " nvfp4 tensors"

<< "qwen3.8-flash-next: " + mode + ", " + st.count().to_s + " non-expert tensors, " + experts_man["files"].size().to_s + " expert shards"
if experts_man["files"].size() != N_LAYERS * 4
  raise "experts_manifest incomplete: " + experts_man["files"].size().to_s + " of " + (N_LAYERS * 4).to_s + " shards; rerun prepare_flash_next.py after the download finishes"

# ---- pipelines ----
bf16_embed_pipe = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "bf16_embedding_lookup.metal")), "bf16_embedding_lookup")
bf16_matvec_pipe = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "bf16_matvec.metal")), "bf16_matvec")
copy_pipe = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "copy_f32_slice.metal")), "copy_f32_slice")
copy_at_pipe = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "copy_f32_at.metal")), "copy_f32_at")
kv_write_pipe = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "kv_write.metal")), "kv_write")
silu_pipe = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "silu_mul.metal")), "silu_mul")
phn_pipe = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "per_head_norm.metal")), "per_head_norm")
argmax_lib = metal_compile_source(device, read_file(SHARED_DIR + "argmax_two_stage.metal"))
argmax_stage1_pipe = metal_pipeline(argmax_lib, "argmax_stage1")
argmax_stage2_pipe = metal_pipeline(argmax_lib, "argmax_stage2")

conv_pipe = metal_pipeline(metal_compile_source(device, read_file(QWEN_DIR + "conv1d_depthwise_step.metal")), "conv1d_depthwise_step")
g_pipe = metal_pipeline(metal_compile_source(device, read_file(QWEN_DIR + "compute_g.metal")), "compute_g")
delta_pipe = metal_pipeline(metal_compile_source(device, read_file(QWEN_DIR + "gated_delta_step.metal")), "gated_delta_step")
sigmoid_pipe = metal_pipeline(metal_compile_source(device, read_file(QWEN_DIR + "sigmoid_inplace.metal")), "sigmoid_f32")
split_pipe = metal_pipeline(metal_compile_source(device, read_file(QWEN_DIR + "split_q_gate.metal")), "split_q_gate")
rope_pipe = metal_pipeline(metal_compile_source(device, read_file(QWEN_DIR + "partial_rope_neox.metal")), "partial_rope_neox")
sdpa_pipe = metal_pipeline(metal_compile_source(device, read_file(QWEN_DIR + "sdpa_decode_hd256.metal")), "sdpa_decode_hd256")
gate_pipe = metal_pipeline(metal_compile_source(device, read_file(QWEN_DIR + "attn_output_gate.metal")), "attn_output_gate")

bf16_wide_lib = metal_compile_source(device, read_file(FN_DIR + "bf16_matvec_wide.metal"))
bf16_w2_pipe = metal_pipeline(bf16_wide_lib, "bf16_matvec_w2")
nvfp4_pipe = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_scaled.metal")), "nvfp4_matvec_mlx_scaled")
grms_pipe = metal_pipeline(metal_compile_source(device, read_file(FN_DIR + "grouped_rms_norm.metal")), "grouped_rms_norm")
hc_lib = metal_compile_source(device, read_file(FN_DIR + "hc_ops.metal"))
silu_div_pipe = metal_pipeline(hc_lib, "silu_div")
hc_mix_reduce_pipe = metal_pipeline(hc_lib, "hc_mix_reduce")
hc_combine_pipe = metal_pipeline(hc_lib, "hc_combine")
router_pipe = metal_pipeline(metal_compile_source(device, read_file(FN_DIR + "router_softmax_topk10.metal")), "router_softmax_topk10")
gather_pipe = metal_pipeline(metal_compile_source(device, read_file(FN_DIR + "moe_gather_nvfp4.metal")), "moe_gather_matvec")
moe_combine_lib = metal_compile_source(device, read_file(FN_DIR + "moe_combine.metal"))
moe_wsum_pipe = metal_pipeline(moe_combine_lib, "moe_weighted_sum")
moe_shared_pipe = metal_pipeline(moe_combine_lib, "moe_shared_combine")
expert_hist_pipe = metal_pipeline(moe_combine_lib, "expert_hist_accum")
rng_sig_pipe = metal_pipeline(metal_compile_source(device, read_file(FN_DIR + "rms_norm_gated_sig.metal")), "rms_norm_gated_sig")
hc_fused_lib = metal_compile_source(device, read_file(FN_DIR + "hc_fused.metal"))
hc_mix_a_pipe = metal_pipeline(hc_fused_lib, "hc_mix_a")
hc_mix_b_pipe = metal_pipeline(hc_fused_lib, "hc_mix_b")
gdn_fused_lib = metal_compile_source(device, read_file(FN_DIR + "gdn_fused.metal"))
conv_split_pipe = metal_pipeline(gdn_fused_lib, "gdn_conv_split")
g_beta_pipe = metal_pipeline(gdn_fused_lib, "gdn_g_beta")
moe_output_pipe = metal_pipeline(gdn_fused_lib, "moe_output")
ple_lib = metal_compile_source(device, read_file(FN_DIR + "ple_ops.metal"))
ple_gate_pipe = metal_pipeline(ple_lib, "ple_gate")
ple_conv_pipe = metal_pipeline(ple_lib, "ple_conv_dilated_step")

# ---- weight loading helpers (identical conventions to qwen38_mlx.w) ----
-> raw_tensor(name)
  d = st.tensor(name)
  metal_buffer_for_mmap(device, st.mmap_for(name), d[:byte_offset], d[:byte_length])

-> sq_tensor(name)
  d = sq.tensor(name)
  metal_buffer_for_mmap(device, sq.mmap, d[:byte_offset], d[:byte_length])

# Matvec weight handle: self-quantized NVFP4 triple when the sidecar has the
# tensor, else the raw bf16 mmap. Consumed by enqueue_mv.
-> mv_tensor(name)
  if selfquant && sq.has?(name)
    [sq_tensor(name), sq_tensor(name + ".scale"), sq_tensor(name + ".global_scale")]
  else
    [raw_tensor(name)]

-> load_bf16(spec)
  name = spec[0]
  n = spec[1]
  dst = spec[2]
  d = st.tensor(name)
  m = st.mmap_for(name)
  i = 0
  while i < n
    off = d[:byte_offset] + i * 2
    bits = m.byte_at(off) | (m.byte_at(off + 1) << 8)
    metal_buffer_write_i32(dst, i, bits << 16)
    i = i + 1

# Norms in this model are Gemma-style (1+w) — stored zero-centered — with the
# single exception of linear_attn.norm (plain w, loaded via load_bf16).
-> load_shifted_norm(spec)
  name = spec[0]
  n = spec[1]
  dst = spec[2]
  d = st.tensor(name)
  m = st.mmap_for(name)
  i = 0
  while i < n
    off = d[:byte_offset] + i * 2
    bits = m.byte_at(off) | (m.byte_at(off + 1) << 8)
    value = ccall("w_float_from_u32_bits", bits << 16) + 1.0
    metal_buffer_write_i32(dst, i, ccall("w_float_to_u32_bits", value))
    i = i + 1

-> load_hc(prefix)
  norm = metal_buffer(device, HC_HIDDEN * 4)
  load_shifted_norm([prefix + "hc_norm.weight", HC_HIDDEN, norm])
  {
    norm: norm,
    down: mv_tensor(prefix + "input_mix_weight_down.weight"),
    up: mv_tensor(prefix + "input_mix_weight_up.weight"),
    inject: st.has?(prefix + "block_inject_weight.weight") ? raw_tensor(prefix + "block_inject_weight.weight") : nil
  }

# ---- fixed weights ----
embed_w = raw_tensor("model.language_model.embed_tokens.weight")
lm_head = mv_tensor("lm_head.weight")
mixer = load_hc("model.language_model.hyper_connection_mixer.")

# GatedDeltaNet q/k l2norm constant scales (l2norm ~= rms*(1/sqrt(DK)); q also
# carries the 1/sqrt(DK) attention scaling).
q_norm_scale = metal_buffer(device, DK * 4)
k_norm_scale = metal_buffer(device, DK * 4)
inv_sqrt_dk = ~1.0 / Math.sqrt(~0.0 + DK)
i = 0
while i < DK
  metal_buffer_write_f32(q_norm_scale, i, inv_sqrt_dk * inv_sqrt_dk)
  metal_buffer_write_f32(k_norm_scale, i, inv_sqrt_dk)
  i = i + 1

# ---- expert shard binding: 4 whole-file mmap buffers per layer + offsets ----
# Mmap handles must outlive the Metal buffers bound to them; retain every one
# here so compile-time free insertion can never unmap live weight pages.
expert_mmaps = []
expert_files = {}
fi = 0
while fi < experts_man["files"].size()
  e = experts_man["files"][fi]
  expert_files[e["layer"].to_s + "_" + e["quarter"].to_s] = e
  fi = fi + 1

dummy_hot = metal_buffer(device, 8)

# Per-layer hot lists from an expert-hist run: hist[l*512+e] u32.
hot_lists = []
if pin_count > 0
  hist_m = File.mmap("/tmp/fn_expert_hist.u32")
  li2 = 0
  while li2 < N_LAYERS
    counts = []
    e2 = 0
    while e2 < N_EXPERTS
      off = (li2 * N_EXPERTS + e2) * 4
      c = hist_m.byte_at(off) | (hist_m.byte_at(off + 1) << 8) | (hist_m.byte_at(off + 2) << 16) | (hist_m.byte_at(off + 3) << 24)
      counts.push(c)
      e2 = e2 + 1
    chosen = []
    k2 = 0
    while k2 < pin_count
      best = -1
      bi2 = -1
      e2 = 0
      while e2 < N_EXPERTS
        if counts[e2] > best
          best = counts[e2]
          bi2 = e2
        e2 = e2 + 1
      chosen.push(bi2)
      counts[bi2] = -1
      k2 = k2 + 1
    hot_lists.push(chosen)
    li2 = li2 + 1

-> bind_expert_layer(li)
  # Quarter files share identical DATA-SECTION-relative layout but differ in
  # header size, so each buffer is bound AT its own data_start and the kernel
  # offsets are data-relative (the absolute-offset version corrupts quarters
  # 1-3 — caught by test_fn_moe_gather.w).
  quarters = []
  qmm = []
  qds = []
  slot_buf = metal_buffer(device, N_EXPERTS * 4)
  q = 0
  while q < 4
    e = expert_files[li.to_s + "_" + q.to_s]
    if e == nil then raise "missing expert shard for layer " + li.to_s + " quarter " + q.to_s
    m = File.mmap(MODEL_DIR + e["file"])
    expert_mmaps.push(m)
    qmm.push(m)
    qds.push(e["data_start"])
    quarters.push(metal_buffer_for_mmap(device, m, e["data_start"], e["file_size"] - e["data_start"]))
    sm = e["slot_map"]
    j = 0
    while j < 128
      metal_buffer_write_i32(slot_buf, q * 128 + j, sm[j])
      j = j + 1
    q = q + 1
  e0 = expert_files[li.to_s + "_0"]
  offs = {}
  mats = ["gate_proj", "up_proj", "down_proj"]
  mi = 0
  while mi < 3
    mm = e0[mats[mi]]
    offs[mats[mi]] = [mm["w0"], mm["w_stride"], mm["s0"], mm["s_stride"], mm["g0"], mm["g_stride"], 0, 0, 0]
    mi = mi + 1
  hot_buf = dummy_hot
  if pin_count > 0
    # Wired overlay reproducing the quarter layout for the layer's top-N
    # experts: [scalars | scales | weights] regions, original strides.
    scal_stride = 24
    scale_stride = offs["gate_proj"][3]
    w_stride = offs["gate_proj"][1]
    scal_base = offs["down_proj"][4] - 4
    scale_base = offs["down_proj"][2]
    w_base = offs["down_proj"][0]
    h_scal = 0
    h_scale = pin_count * scal_stride
    h_w = h_scale + pin_count * scale_stride
    hot_buf = metal_buffer(device, h_w + pin_count * w_stride)
    chosen = hot_lists[li]
    j = 0
    while j < pin_count
      ge = chosen[j]
      q = ge / 128
      e = expert_files[li.to_s + "_" + q.to_s]
      slot = e["slot_map"][ge % 128]
      src = qds[q]
      metal_buffer_write_from_mmap(hot_buf, h_scal + j * scal_stride, qmm[q], src + scal_base + slot * scal_stride, scal_stride)
      metal_buffer_write_from_mmap(hot_buf, h_scale + j * scale_stride, qmm[q], src + scale_base + slot * scale_stride, scale_stride)
      metal_buffer_write_from_mmap(hot_buf, h_w + j * w_stride, qmm[q], src + w_base + slot * w_stride, w_stride)
      metal_buffer_write_i32(slot_buf, ge, j | 1073741824)
      j = j + 1
    mi = 0
    while mi < 3
      o = offs[mats[mi]]
      o[6] = h_w + (o[0] - w_base)
      o[7] = h_scale + (o[2] - scale_base)
      o[8] = h_scal + (o[4] - scal_base)
      mi = mi + 1
  { quarters: quarters, slot_map: slot_buf, offs: offs, hot: hot_buf }

# ---- per-layer weights ----
layers = []
li = 0
while li < N_LAYERS
  prefix = "model.language_model.layers." + li.to_s + "."
  if (li % 8) == 0 then << "  loading layer " + li.to_s
  base = {
    attn_hc: load_hc(prefix + "attn_hyper_connection."),
    mlp_hc: load_hc(prefix + "mlp_hyper_connection."),
    router: mv_tensor(prefix + "mlp.gate.weight"),
    sh_gate: mv_tensor(prefix + "mlp.shared_expert.gate_proj.weight"),
    sh_up: mv_tensor(prefix + "mlp.shared_expert.up_proj.weight"),
    sh_down: mv_tensor(prefix + "mlp.shared_expert.down_proj.weight"),
    sh_seg: raw_tensor(prefix + "mlp.shared_expert_gate.weight"),
    experts: bind_expert_layer(li)
  }
  if st.has?(prefix + "linear_attn.A_log")
    conv_w = metal_buffer(device, QKV_DIM * 4 * 4)
    alog = metal_buffer(device, HV * 4)
    dtb = metal_buffer(device, HV * 4)
    ln_w = metal_buffer(device, DV * 4)
    load_bf16([prefix + "linear_attn.conv1d.weight", QKV_DIM * 4, conv_w])
    load_bf16([prefix + "linear_attn.A_log", HV, alog])
    load_bf16([prefix + "linear_attn.dt_bias", HV, dtb])
    load_bf16([prefix + "linear_attn.norm.weight", DV, ln_w])
    base[:kind] = "mamba"
    base[:qkv] = mv_tensor(prefix + "linear_attn.in_proj_qkv.weight")
    base[:z] = mv_tensor(prefix + "linear_attn.in_proj_z.weight")
    base[:a] = raw_tensor(prefix + "linear_attn.in_proj_a.weight")
    base[:b] = raw_tensor(prefix + "linear_attn.in_proj_b.weight")
    base[:conv] = conv_w
    base[:alog] = alog
    base[:dtb] = dtb
    base[:linear_norm] = ln_w
    base[:out] = mv_tensor(prefix + "linear_attn.out_proj.weight")
    base[:cs_a] = metal_buffer(device, 3 * QKV_DIM * 4)
    base[:cs_b] = metal_buffer(device, 3 * QKV_DIM * 4)
    base[:ss_a] = metal_buffer(device, HV * DV * DK * 4)
    base[:ss_b] = metal_buffer(device, HV * DV * DK * 4)
    base[:ping] = 0
  else
    qn = metal_buffer(device, HEAD_DIM * 4)
    kn = metal_buffer(device, HEAD_DIM * 4)
    load_shifted_norm([prefix + "self_attn.q_norm.weight", HEAD_DIM, qn])
    load_shifted_norm([prefix + "self_attn.k_norm.weight", HEAD_DIM, kn])
    base[:kind] = "full"
    base[:q] = mv_tensor(prefix + "self_attn.q_proj.weight")
    base[:k] = mv_tensor(prefix + "self_attn.k_proj.weight")
    base[:v] = mv_tensor(prefix + "self_attn.v_proj.weight")
    base[:out] = mv_tensor(prefix + "self_attn.o_proj.weight")
    base[:qn] = qn
    base[:kn] = kn
    base[:k_cache] = metal_buffer(device, MAX_POS * KV_DIM * 4)
    base[:v_cache] = metal_buffer(device, MAX_POS * KV_DIM * 4)
  if li == PLE_LAYER
    pp = prefix + "ple."
    nk = metal_buffer(device, HC_HIDDEN * 4)
    nq = metal_buffer(device, HC_HIDDEN * 4)
    nc = metal_buffer(device, HC_HIDDEN * 4)
    pconv = metal_buffer(device, HC_HIDDEN * 4 * 4)
    load_shifted_norm([pp + "norm_key.weight", HC_HIDDEN, nk])
    load_shifted_norm([pp + "norm_query.weight", HC_HIDDEN, nq])
    load_shifted_norm([pp + "norm_conv.weight", HC_HIDDEN, nc])
    load_bf16([pp + "conv1d.weight", HC_HIDDEN * 4, pconv])
    base[:ple] = {
      key: mv_tensor(pp + "key_proj.weight"),
      value: mv_tensor(pp + "value_proj.weight"),
      norm_key: nk,
      norm_query: nq,
      norm_conv: nc,
      conv: pconv,
      cs_a: metal_buffer(device, PLE_STATE * HC_HIDDEN * 4),
      cs_b: metal_buffer(device, PLE_STATE * HC_HIDDEN * 4),
      ping: 0
    }
  layers.push(base)
  li = li + 1

# ---- PLE host-side n-gram machinery ----
ple_mult = ple_man["layer_multipliers"]
ple_sizes = ple_man["ngram_heads_vocab_sizes"]
ple_offsets = ple_man["ngram_heads_offsets"]
ple_shards = ple_man["shards"]
ple_shard_rows = ple_shards[0]["shape"][0]
ple_head_dim = ple_shards[0]["shape"][1]
ple_scale = ple_man["weight_scale"][0]
# Previous-2-token context for the n-gram hash. Array, not scalars: a scalar
# assignment inside ple_advance would SHADOW the global and silently leave the
# context stuck at EOS (the classic fn-body scoping trap).
ple_ctx = [EOS_TOKEN, EOS_TOKEN]
ple_mmaps = {}

# e4m3 -> f32 LUT (sign * (exp==0 ? man/8 * 2^-6 : (1+man/8) * 2^(exp-7))).
ple_e4m3 = []
bi = 0
while bi < 256
  sign = (bi & 128) != 0 ? ~0.0 - 1.0 : ~1.0
  ex = (bi >> 3) & 15
  man = bi & 7
  value = ~0.0
  if ex == 0
    value = (~0.0 + man) / 8.0 * Math.pow(2.0, ~0.0 - 6.0)
  else
    value = (~1.0 + (~0.0 + man) / 8.0) * Math.pow(2.0, ~0.0 + ex - 7.0)
  ple_e4m3.push(sign * value)
  bi = bi + 1

-> ple_shard_mmap(s)
  key = s.to_s
  if ple_mmaps[key] == nil
    ple_mmaps[key] = File.mmap(MODEL_DIR + ple_shards[s]["file"])
  ple_mmaps[key]

# Compute the 16 hashed n-gram row ids for the current token and gather the
# fp8 rows into e_buf as f32. Heads 0-7 = bigram, 8-15 = trigram.
-> ple_gather(spec)
  tok = spec[0]
  dst = spec[1]
  t0 = tok ## i64
  m0 = ple_mult[0] ## i64
  m1 = ple_mult[1] ## i64
  m2 = ple_mult[2] ## i64
  c1 = ple_ctx[0] ## i64
  c2 = ple_ctx[1] ## i64
  mixed2 = (t0 * m0) ^ (c1 * m1)
  mixed3 = mixed2 ^ (c2 * m2)
  h = 0
  while h < 16
    mixed = h < 8 ? mixed2 : mixed3
    row = (mixed % (ple_sizes[h] ## i64)) + (ple_offsets[h] ## i64)
    s = (row / (ple_shard_rows ## i64)).to_i()
    r = (row % (ple_shard_rows ## i64)).to_i()
    m = ple_shard_mmap(s)
    off = ple_shards[s]["offset"] + r * ple_head_dim
    j = 0
    while j < ple_head_dim
      metal_buffer_write_f32(dst, h * ple_head_dim + j, ple_e4m3[m.byte_at(off + j)] * ple_scale)
      j = j + 1
    h = h + 1

-> ple_advance(tok)
  if tok == EOS_TOKEN
    ple_ctx[1] = EOS_TOKEN
    ple_ctx[0] = EOS_TOKEN
  else
    ple_ctx[1] = ple_ctx[0]
    ple_ctx[0] = tok

# ---- scratch buffers ----
H = metal_buffer(device, HC_HIDDEN * 4)
n_tmp = metal_buffer(device, HC_HIDDEN * 4)
lowrank_tmp = metal_buffer(device, HC_LOWRANK * 4)
upraw_tmp = metal_buffer(device, HC_HIDDEN * 4)
inj_tmp = metal_buffer(device, HC_COUNT * 4)
rms_tmp = metal_buffer(device, HC_COUNT * 4)
xn = metal_buffer(device, HIDDEN * 4)
y_tmp = metal_buffer(device, HIDDEN * 4)
h_embed = metal_buffer(device, HIDDEN * 4)

qkv_tmp = metal_buffer(device, QKV_DIM * 4)
z_tmp = metal_buffer(device, V_DIM * 4)
a_tmp = metal_buffer(device, HV * 4)
b_tmp = metal_buffer(device, HV * 4)
conv_tmp = metal_buffer(device, QKV_DIM * 4)
mq_tmp = metal_buffer(device, Q_DIM * 4)
mk_tmp = metal_buffer(device, K_DIM * 4)
mv_tmp = metal_buffer(device, V_DIM * 4)
g_tmp = metal_buffer(device, HV * 4)
beta_tmp = metal_buffer(device, HV * 4)
delta_tmp = metal_buffer(device, V_DIM * 4)
mamba_norm_tmp = metal_buffer(device, V_DIM * 4)

qfull_tmp = metal_buffer(device, QFULL_DIM * 4)
queries_tmp = metal_buffer(device, ATTN_DIM * 4)
attn_gate_tmp = metal_buffer(device, ATTN_DIM * 4)
k_tmp = metal_buffer(device, KV_DIM * 4)
v_tmp = metal_buffer(device, KV_DIM * 4)
attn_tmp = metal_buffer(device, ATTN_DIM * 4)
cos_tmp = metal_buffer(device, ROT_HALF * 4)
sin_tmp = metal_buffer(device, ROT_HALF * 4)

router_logits = metal_buffer(device, N_EXPERTS * 4)
top_idx = metal_buffer(device, TOP_K * 4)
top_w = metal_buffer(device, TOP_K * 4)
eg_tmp = metal_buffer(device, TOP_K * MOE_FFN * 4)
eu_tmp = metal_buffer(device, TOP_K * MOE_FFN * 4)
eh_tmp = metal_buffer(device, TOP_K * MOE_FFN * 4)
ed_tmp = metal_buffer(device, TOP_K * HIDDEN * 4)
routed_tmp = metal_buffer(device, HIDDEN * 4)
sg_tmp = metal_buffer(device, SHARED_FFN * 4)
su_tmp = metal_buffer(device, SHARED_FFN * 4)
sh_tmp = metal_buffer(device, SHARED_FFN * 4)
shared_tmp = metal_buffer(device, HIDDEN * 4)
seg_tmp = metal_buffer(device, 4)

e_buf = metal_buffer(device, HIDDEN * 4)
ple_key_tmp = metal_buffer(device, HC_HIDDEN * 4)
ple_kn_tmp = metal_buffer(device, HC_HIDDEN * 4)
ple_qn_tmp = metal_buffer(device, HC_HIDDEN * 4)
ple_v_tmp = metal_buffer(device, HIDDEN * 4)
ple_gv_tmp = metal_buffer(device, HC_HIDDEN * 4)
ple_nc_tmp = metal_buffer(device, HC_HIDDEN * 4)

# Per-token scalar slots as real buffers: their CONTENTS are rewritten each
# token, so recorded programs (and ICBs, whose args freeze at record time)
# never need re-encoding.
pos_buf = metal_buffer(device, 4)
pos1_buf = metal_buffer(device, 4)
tok_buf = metal_buffer(device, 4)
hist_buf = metal_buffer(device, N_LAYERS * N_EXPERTS * 4)
if expert_hist
  hz = 0
  while hz < N_LAYERS * N_EXPERTS
    metal_buffer_write_i32(hist_buf, hz, 0)
    hz = hz + 1
logits = metal_buffer(device, N_VOCAB * 4)
argmax_out = metal_buffer(device, 4)
argmax_partial_values = metal_buffer(device, ARGMAX_CHUNKS * 4)
argmax_partial_indices = metal_buffer(device, ARGMAX_CHUNKS * 4)


# ---- prebuilt dispatch programs -------------------------------------------
# Host encode measured 18ms/round (FN_TIME): the per-dispatch boxed glue —
# fresh args arrays, hash lookups, handle unpacking — dominates the token.
# Each layer's dispatch sequence is baked into a flat step list at load
# (two variants where the GDN/PLE ping-pong swaps state buffers); per token
# only the pos-dependent slots are mutated in place. Step encoding:
#   [0, pipe, args, n_groups, tg_size]  -> metal_dispatch_groups
#   [2, pipe, args, n, 0]               -> metal_dispatch_n
#   [1, nil, bufs, 0, 0]                -> scoped barrier
# The golden/ablation/expert-hist modes keep the original per-call path.
-> prog_mv(spec)
  prog = spec[0]
  h = spec[1]
  input = spec[2]
  output = spec[3]
  kdim = spec[4]
  rows = spec[5]
  if h.size() == 3
    prog.push([0, nvfp4_pipe, [h[0], h[1], input, output, kdim, h[2]], rows / 8, 64])
  elsif rows >= 320
    prog.push([0, bf16_w2_pipe, [h[0], input, output, kdim, rows], (rows + 3) / 4, 64])
  else
    prog.push([0, bf16_matvec_pipe, [h[0], input, output, kdim], rows, 32])

-> prog_hc_mix(spec)
  prog = spec[0]
  hc = spec[1]
  prog.push([0, grms_pipe, [H, hc[:norm], n_tmp, HIDDEN, EPS], HC_COUNT, 256])
  prog.push([1, nil, [n_tmp], 0, 0])
  prog_mv([prog, hc[:down], n_tmp, lowrank_tmp, HC_HIDDEN, HC_LOWRANK])
  prog.push([0, bf16_matvec_pipe, [hc[:inject], n_tmp, inj_tmp, HC_HIDDEN], HC_COUNT, 32])
  prog.push([1, nil, [lowrank_tmp], 0, 0])
  prog.push([2, silu_div_pipe, [lowrank_tmp, lowrank_tmp, ~0.0 + HC_COUNT, HC_LOWRANK], HC_LOWRANK, 0])
  prog.push([1, nil, [lowrank_tmp], 0, 0])
  prog_mv([prog, hc[:up], lowrank_tmp, upraw_tmp, HC_LOWRANK, HC_HIDDEN])
  prog.push([1, nil, [upraw_tmp], 0, 0])
  prog.push([2, hc_mix_reduce_pipe, [upraw_tmp, n_tmp, xn, HC_COUNT, HIDDEN], HIDDEN, 0])
  prog.push([1, nil, [xn, inj_tmp], 0, 0])

-> prog_hc_combine(prog)
  prog.push([2, hc_combine_pipe, [H, y_tmp, inj_tmp, HC_COUNT, HIDDEN], HC_HIDDEN, 0])
  prog.push([1, nil, [H], 0, 0])

-> prog_mamba(spec)
  prog = spec[0]
  lyr = spec[1]
  ping = spec[2]
  cs_in = ping == 0 ? lyr[:cs_a] : lyr[:cs_b]
  cs_out = ping == 0 ? lyr[:cs_b] : lyr[:cs_a]
  ss_in = ping == 0 ? lyr[:ss_a] : lyr[:ss_b]
  ss_out = ping == 0 ? lyr[:ss_b] : lyr[:ss_a]
  prog_mv([prog, lyr[:qkv], xn, qkv_tmp, HIDDEN, QKV_DIM])
  prog_mv([prog, lyr[:z], xn, z_tmp, HIDDEN, V_DIM])
  prog.push([0, bf16_matvec_pipe, [lyr[:a], xn, a_tmp, HIDDEN], HV, 32])
  prog.push([0, bf16_matvec_pipe, [lyr[:b], xn, b_tmp, HIDDEN], HV, 32])
  prog.push([1, nil, [qkv_tmp], 0, 0])
  prog.push([2, conv_split_pipe, [lyr[:conv], cs_in, qkv_tmp, mq_tmp, mk_tmp, mv_tmp, cs_out, QKV_DIM, Q_DIM, K_DIM], QKV_DIM, 0])
  prog.push([1, nil, [mq_tmp, mk_tmp, mv_tmp, a_tmp, b_tmp], 0, 0])
  prog.push([0, phn_pipe, [mq_tmp, q_norm_scale, DK, ~1.0 / DK, EPS / DK], HK, 32])
  prog.push([0, phn_pipe, [mk_tmp, k_norm_scale, DK, ~1.0 / DK, EPS / DK], HK, 32])
  prog.push([2, g_beta_pipe, [a_tmp, b_tmp, lyr[:alog], lyr[:dtb], g_tmp, beta_tmp, HV], HV, 0])
  prog.push([1, nil, [mq_tmp, mk_tmp, g_tmp, beta_tmp], 0, 0])
  prog.push([3, delta_pipe, [mq_tmp, mk_tmp, mv_tmp, g_tmp, beta_tmp, ss_in, delta_tmp, ss_out, HK, HV, DK, DV], 0, 0])
  prog.push([1, nil, [delta_tmp, z_tmp], 0, 0])
  prog.push([0, rng_sig_pipe, [delta_tmp, z_tmp, lyr[:linear_norm], mamba_norm_tmp, DV, EPS], HV, 32])
  prog.push([1, nil, [mamba_norm_tmp], 0, 0])
  prog_mv([prog, lyr[:out], mamba_norm_tmp, y_tmp, V_DIM, HIDDEN])
  prog.push([1, nil, [y_tmp], 0, 0])

-> prog_full(spec)
  prog = spec[0]
  lyr = spec[1]
  kv_k = [k_tmp, lyr[:k_cache], pos_buf, KV_DIM]
  kv_v = [v_tmp, lyr[:v_cache], pos_buf, KV_DIM]
  sdpa = [queries_tmp, lyr[:k_cache], lyr[:v_cache], attn_tmp, GQA, pos1_buf, HEAD_DIM, KV_DIM, ATTN_SCALE]
  prog_mv([prog, lyr[:q], xn, qfull_tmp, HIDDEN, QFULL_DIM])
  prog_mv([prog, lyr[:k], xn, k_tmp, HIDDEN, KV_DIM])
  prog_mv([prog, lyr[:v], xn, v_tmp, HIDDEN, KV_DIM])
  prog.push([1, nil, [qfull_tmp], 0, 0])
  prog.push([2, split_pipe, [qfull_tmp, queries_tmp, attn_gate_tmp, N_HEADS, HEAD_DIM], ATTN_DIM, 0])
  prog.push([1, nil, [queries_tmp, k_tmp], 0, 0])
  prog.push([0, phn_pipe, [queries_tmp, lyr[:qn], HEAD_DIM, ~1.0 / HEAD_DIM, EPS], N_HEADS, 32])
  prog.push([0, phn_pipe, [k_tmp, lyr[:kn], HEAD_DIM, ~1.0 / HEAD_DIM, EPS], N_KV_HEADS, 32])
  prog.push([1, nil, [queries_tmp, k_tmp], 0, 0])
  prog.push([2, rope_pipe, [queries_tmp, cos_tmp, sin_tmp, HEAD_DIM, ROT_HALF, N_HEADS], N_HEADS * ROT_HALF, 0])
  prog.push([2, rope_pipe, [k_tmp, cos_tmp, sin_tmp, HEAD_DIM, ROT_HALF, N_KV_HEADS], N_KV_HEADS * ROT_HALF, 0])
  prog.push([1, nil, [queries_tmp, k_tmp, v_tmp], 0, 0])
  prog.push([2, kv_write_pipe, kv_k, KV_DIM, 0])
  prog.push([2, kv_write_pipe, kv_v, KV_DIM, 0])
  prog.push([1, nil, [lyr[:k_cache], lyr[:v_cache]], 0, 0])
  prog.push([0, sdpa_pipe, sdpa, N_HEADS, 256])
  prog.push([1, nil, [attn_tmp, attn_gate_tmp], 0, 0])
  prog.push([2, gate_pipe, [attn_tmp, attn_gate_tmp, ATTN_DIM], ATTN_DIM, 0])
  prog.push([1, nil, [attn_tmp], 0, 0])
  prog_mv([prog, lyr[:out], attn_tmp, y_tmp, ATTN_DIM, HIDDEN])
  prog.push([1, nil, [y_tmp], 0, 0])

-> prog_moe(spec)
  prog = spec[0]
  lyr = spec[1]
  ex = lyr[:experts]
  og = ex[:offs]["gate_proj"]
  ou = ex[:offs]["up_proj"]
  od = ex[:offs]["down_proj"]
  q = ex[:quarters]
  prog_mv([prog, lyr[:router], xn, router_logits, HIDDEN, N_EXPERTS])
  prog_mv([prog, lyr[:sh_gate], xn, sg_tmp, HIDDEN, SHARED_FFN])
  prog_mv([prog, lyr[:sh_up], xn, su_tmp, HIDDEN, SHARED_FFN])
  prog.push([0, bf16_matvec_pipe, [lyr[:sh_seg], xn, seg_tmp, HIDDEN], 1, 32])
  prog.push([1, nil, [router_logits, sg_tmp, su_tmp], 0, 0])
  prog.push([0, router_pipe, [router_logits, top_idx, top_w], 1, 512])
  prog.push([2, silu_pipe, [sg_tmp, su_tmp, sh_tmp, SHARED_FFN], SHARED_FFN, 0])
  prog.push([1, nil, [top_idx, sh_tmp], 0, 0])
  prog.push([0, gather_pipe, [q[0], q[1], q[2], q[3], top_idx, ex[:slot_map], xn, eg_tmp, HIDDEN, MOE_FFN, og[0], og[1], og[2], og[3], og[4], og[5], 0, ex[:hot], og[6], og[7], og[8]], TOP_K * (MOE_FFN / 8), 64])
  prog.push([0, gather_pipe, [q[0], q[1], q[2], q[3], top_idx, ex[:slot_map], xn, eu_tmp, HIDDEN, MOE_FFN, ou[0], ou[1], ou[2], ou[3], ou[4], ou[5], 0, ex[:hot], ou[6], ou[7], ou[8]], TOP_K * (MOE_FFN / 8), 64])
  prog_mv([prog, lyr[:sh_down], sh_tmp, shared_tmp, SHARED_FFN, HIDDEN])
  prog.push([1, nil, [eg_tmp, eu_tmp], 0, 0])
  prog.push([2, silu_pipe, [eg_tmp, eu_tmp, eh_tmp, TOP_K * MOE_FFN], TOP_K * MOE_FFN, 0])
  prog.push([1, nil, [eh_tmp], 0, 0])
  prog.push([0, gather_pipe, [q[0], q[1], q[2], q[3], top_idx, ex[:slot_map], eh_tmp, ed_tmp, MOE_FFN, HIDDEN, od[0], od[1], od[2], od[3], od[4], od[5], MOE_FFN, ex[:hot], od[6], od[7], od[8]], TOP_K * (HIDDEN / 8), 64])
  prog.push([1, nil, [ed_tmp, top_w, shared_tmp, seg_tmp], 0, 0])
  prog.push([2, moe_output_pipe, [ed_tmp, top_w, shared_tmp, seg_tmp, y_tmp, TOP_K, HIDDEN], HIDDEN, 0])
  prog.push([1, nil, [y_tmp], 0, 0])

-> prog_ple(spec)
  prog = spec[0]
  lyr = spec[1]
  ping = spec[2]
  pp = lyr[:ple]
  cs_in = ping == 0 ? pp[:cs_a] : pp[:cs_b]
  cs_out = ping == 0 ? pp[:cs_b] : pp[:cs_a]
  prog_mv([prog, pp[:key], e_buf, ple_key_tmp, HIDDEN, HC_HIDDEN])
  prog_mv([prog, pp[:value], e_buf, ple_v_tmp, HIDDEN, HIDDEN])
  prog.push([0, grms_pipe, [H, pp[:norm_query], ple_qn_tmp, HIDDEN, EPS], HC_COUNT, 256])
  prog.push([1, nil, [ple_key_tmp, ple_qn_tmp], 0, 0])
  prog.push([0, grms_pipe, [ple_key_tmp, pp[:norm_key], ple_kn_tmp, HIDDEN, EPS], HC_COUNT, 256])
  prog.push([1, nil, [ple_kn_tmp, ple_v_tmp], 0, 0])
  prog.push([0, ple_gate_pipe, [ple_kn_tmp, ple_qn_tmp, ple_v_tmp, ple_gv_tmp, HIDDEN], HC_COUNT, 256])
  prog.push([1, nil, [ple_gv_tmp], 0, 0])
  prog.push([0, grms_pipe, [ple_gv_tmp, pp[:norm_conv], ple_nc_tmp, HIDDEN, EPS], HC_COUNT, 256])
  prog.push([1, nil, [ple_nc_tmp], 0, 0])
  prog.push([2, ple_conv_pipe, [pp[:conv], cs_in, ple_nc_tmp, ple_gv_tmp, H, cs_out, HC_HIDDEN], HC_HIDDEN, 0])
  prog.push([1, nil, [H], 0, 0])

-> run_prog(prog)
  i = 0
  n = prog.size()
  while i < n
    st = prog[i]
    k = st[0]
    if k == 0
      metal_dispatch_groups(queue, st[1], st[2], st[3], st[4])
    elsif k == 2
      metal_dispatch_n(queue, st[1], st[2], st[3])
    elsif k == 1
      if concurrent then metal_batch_barrier_resources(queue, st[2])
    else
      metal_dispatch_3d(queue, st[1], st[2], 1, DV / 4, HV, 32, 4, 1)
    i = i + 1

# Build the per-layer programs (after every scratch buffer exists).
li = 0
while li < N_LAYERS
  lyr = layers[li]
  if lyr[:kind] == "mamba"
    pa = []
    pb = []
    prog_hc_mix([pa, lyr[:attn_hc]])
    prog_hc_mix([pb, lyr[:attn_hc]])
    prog_mamba([pa, lyr, 0])
    prog_mamba([pb, lyr, 1])
    prog_hc_combine(pa)
    prog_hc_combine(pb)
    prog_hc_mix([pa, lyr[:mlp_hc]])
    prog_hc_mix([pb, lyr[:mlp_hc]])
    prog_moe([pa, lyr])
    prog_moe([pb, lyr])
    prog_hc_combine(pa)
    prog_hc_combine(pb)
    lyr[:prog_a] = pa
    lyr[:prog_b] = pb
  else
    # ONE program for attention layers: prog_full registers the mutable
    # kv/sdpa arg arrays on the layer, and a second build would orphan them.
    pa = []
    prog_hc_mix([pa, lyr[:attn_hc]])
    prog_full([pa, lyr])
    prog_hc_combine(pa)
    prog_hc_mix([pa, lyr[:mlp_hc]])
    prog_moe([pa, lyr])
    prog_hc_combine(pa)
    lyr[:prog_a] = pa
    lyr[:prog_b] = pa
  if lyr[:ple] != nil
    ppa = []
    ppb = []
    prog_ple([ppa, lyr, 0])
    prog_ple([ppb, lyr, 1])
    lyr[:ple_prog_a] = ppa
    lyr[:ple_prog_b] = ppb
  li = li + 1
head_prog = []
prog_hc_mix_head = [0, grms_pipe, [H, mixer[:norm], n_tmp, HIDDEN, EPS], HC_COUNT, 256]
head_prog.push(prog_hc_mix_head)
head_prog.push([1, nil, [n_tmp], 0, 0])
prog_mv([head_prog, mixer[:down], n_tmp, lowrank_tmp, HC_HIDDEN, HC_LOWRANK])
head_prog.push([1, nil, [lowrank_tmp], 0, 0])
head_prog.push([2, silu_div_pipe, [lowrank_tmp, lowrank_tmp, ~0.0 + HC_COUNT, HC_LOWRANK], HC_LOWRANK, 0])
head_prog.push([1, nil, [lowrank_tmp], 0, 0])
prog_mv([head_prog, mixer[:up], lowrank_tmp, upraw_tmp, HC_LOWRANK, HC_HIDDEN])
head_prog.push([1, nil, [upraw_tmp], 0, 0])
head_prog.push([2, hc_mix_reduce_pipe, [upraw_tmp, n_tmp, xn, HC_COUNT, HIDDEN], HIDDEN, 0])
head_prog.push([1, nil, [xn], 0, 0])
prog_mv([head_prog, lm_head, xn, logits, HIDDEN, N_VOCAB])
head_prog.push([1, nil, [logits], 0, 0])
head_prog.push([0, argmax_stage1_pipe, [logits, argmax_partial_values, argmax_partial_indices, N_VOCAB, ARGMAX_CHUNKS, 1], ARGMAX_CHUNKS, 256])
head_prog.push([1, nil, [argmax_partial_values, argmax_partial_indices], 0, 0])
head_prog.push([0, argmax_stage2_pipe, [argmax_partial_values, argmax_partial_indices, argmax_out, ARGMAX_CHUNKS, 1], 1, 256])
embed_args = [embed_w, h_embed, tok_buf, HIDDEN]

# ---- indirect command buffers: whole-token replay ----
# FN_ICB=1 records the full token (embed + 48 layers + head) into two ICBs
# (even/odd GDN/PLE state parity) and executes each token with a single
# executeCommandsInBuffer inside a SERIAL batch (implicit ordering; measured
# equivalent to scoped barriers). Args are frozen at record time — per-token
# scalars live in pos_buf/pos1_buf/tok_buf whose contents the host rewrites.
use_icb = ccall("__w_env", "FN_ICB") == "1"

-> icb_tg_for(n)
  d = 256
  while d > 1
    if n % d == 0 then return d
    d = d / 2
  1

# Scalar args must be REAL metal buffers inside ICBs (C-side 4-byte buffers
# read as garbage from ICB commands — empirically; .w-created ones work).
# Pool them by value so recording swaps every int/float arg for a buffer.
# One FRESH buffer per binding — value-pooled buffers bound at two indices
# of the same ICB command (Q_DIM==K_DIM, DK==DV) silently break that
# command's writes.
-> icb_scalar(v)
  b = metal_buffer(device, 4)
  if type(v) == "Float"
    metal_buffer_write_i32(b, 0, ccall("w_float_to_u32_bits", v))
  else
    metal_buffer_write_i32(b, 0, v)
  b

-> icb_args(args)
  out = []
  i = 0
  n = args.size()
  while i < n
    a = args[i]
    t = type(a)
    if t == "Int" || t == "Float"
      out.push(icb_scalar(a))
    else
      out.push(a)
    i = i + 1
  out

# ICB build state: [icb, since-last-barrier count, segs array]. The recorded
# barrier structure becomes segment lengths for the C-side segmented
# executor (ICB commands run concurrently within one executeCommands range).
-> icb_emit(spec)
  bstate = spec[0]
  st = spec[1]
  k = st[0]
  if k == 1
    icb_break(bstate)
    return
  if k == 0
    metal_icb_add(bstate[0], st[1], icb_args(st[2]), st[3], st[4])
  elsif k == 2
    n = st[3]
    tg = icb_tg_for(n)
    metal_icb_add(bstate[0], st[1], icb_args(st[2]), n / tg, tg)
  elsif k == 3
    metal_icb_add_3d(bstate[0], st[1], icb_args(st[2]), 1, DV / 4, HV, 32, 4, 1)
  bstate[1] = bstate[1] + 1

-> icb_emit_prog(spec)
  bstate = spec[0]
  prog = spec[1]
  i = 0
  n = prog.size()
  while i < n
    icb_emit([bstate, prog[i]])
    i = i + 1

-> icb_break(bstate)
  if bstate[1] > 0
    bstate[2].push(bstate[1])
    bstate[4] = bstate[4] + bstate[1]
    bstate[1] = 0

# One token is ~1820 commands, split deterministically into two ICB parts at
# layer 24. CRITICAL: metal_icb_new with constant args gets CSE'd by the
# compiler (ccalls treated as pure), silently making every "new" ICB the
# same object — every part must pass a DISTINCT max so the calls survive.
icb_part_seq = [0]
-> build_token_part(spec)
  parity = spec[0]
  lo = spec[1]
  hi = spec[2]
  with_embed = spec[3]
  with_head = spec[4]
  icb_part_seq[0] = icb_part_seq[0] + 1
  bstate = [metal_icb_new(device, 2000 + icb_part_seq[0]), 0, [], [], 0, 0]
  if with_embed == 1
    metal_icb_add(bstate[0], bf16_embed_pipe, icb_args(embed_args), HIDDEN / 256, 256)
    bstate[1] = 1
    icb_break(bstate)
    si = 0
    while si < HC_COUNT
      metal_icb_add(bstate[0], copy_at_pipe, icb_args([h_embed, H, 0, si * HIDDEN, HIDDEN]), HIDDEN / 256, 256)
      bstate[1] = bstate[1] + 1
      si = si + 1
    icb_break(bstate)
  li = lo
  while li < hi
    lyr = layers[li]
    if lyr[:ple] != nil
      icb_emit_prog([bstate, parity == 0 ? lyr[:ple_prog_a] : lyr[:ple_prog_b]])
    icb_emit_prog([bstate, parity == 0 || lyr[:kind] == "full" ? lyr[:prog_a] : lyr[:prog_b]])
    icb_break(bstate)
    li = li + 1
  if with_head == 1
    icb_emit_prog([bstate, head_prog])
    icb_break(bstate)
  << "  icb part: " + bstate[4].to_s + " commands, " + bstate[2].size().to_s + " segments"
  [bstate[0], bstate[2]]

-> build_token_icb(parity)
  [build_token_part([parity, 0, 24, 1, 0]), build_token_part([parity, 24, N_LAYERS, 0, 1])]

icb_even = nil
icb_odd = nil
icb_even_segs = nil
icb_odd_segs = nil
icb_parity = [0]
if use_icb
  icb_even = build_token_icb(0)
  icb_odd = build_token_icb(1)
  << "ICBs recorded: " + icb_even.size().to_s + " parts/token"

probe_k = 0
if use_icb && ccall("__w_env", "FN_ICB_PROBE2") != nil && ccall("__w_env", "FN_ICB_PROBE2") != ""
  probe_k = ccall("__w_env", "FN_ICB_PROBE2").to_i()
if probe_k > 0
  seedi = 0
  while seedi < HC_HIDDEN
    metal_buffer_write_f32(H, seedi, ~0.001 * (seedi % 97))
    if seedi < HIDDEN then metal_buffer_write_f32(xn, seedi, ~0.001 * (seedi % 89))
    seedi = seedi + 1
  bs3 = [metal_icb_new(device, 4096), 0, []]
  pr3 = layers[0][:prog_a]
  ci3 = 0
  lim = probe_k < pr3.size() ? probe_k : pr3.size()
  while ci3 < lim
    icb_emit([bs3, pr3[ci3]])
    ci3 = ci3 + 1
  icb_break(bs3)
  metal_batch_begin(queue)
  metal_icb_execute_segments(queue, bs3[0], bs3[2])
  metal_batch_commit(queue)
  << "probe2 k=" + lim.to_s + " cmds=" + bs3[1].to_s + ": cs_b " + metal_buffer_read_f32(layers[0][:cs_b], 2 * QKV_DIM).to_s + " / " + metal_buffer_read_f32(layers[0][:cs_b], 2 * QKV_DIM + 7).to_s

-> forward_icb(token_id, pos)
  ft0 = fn_time ? ccall("__w_clock_ms") : ~0.0
  build_rope(pos)
  ple_gather([token_id, e_buf])
  metal_buffer_write_i32(tok_buf, 0, token_id)
  metal_buffer_write_i32(pos_buf, 0, pos)
  metal_buffer_write_i32(pos1_buf, 0, pos + 1)
  ft1 = fn_time ? ccall("__w_clock_ms") : ~0.0
  metal_batch_begin(queue)
  parts = icb_parity[0] == 0 ? icb_even : icb_odd
  pi = 0
  while pi < parts.size()
    metal_icb_execute_segments(queue, parts[pi][0], parts[pi][1])
    pi = pi + 1
  ft2 = fn_time ? ccall("__w_clock_ms") : ~0.0
  metal_batch_commit(queue)
  # flip every GDN/PLE ping so the non-ICB paths stay consistent
  icb_parity[0] = 1 - icb_parity[0]
  li = 0
  while li < N_LAYERS
    lyr = layers[li]
    if lyr[:kind] == "mamba" then lyr[:ping] = 1 - lyr[:ping]
    if lyr[:ple] != nil then lyr[:ple][:ping] = 1 - lyr[:ple][:ping]
    li = li + 1
  ple_advance(token_id)
  result = metal_buffer_read_i32(argmax_out, 0)
  if fn_time
    encode_ms[0] = encode_ms[0] + (ft1 - ft0)
    encode_ms[1] = encode_ms[1] + (ft2 - ft1)
    encode_ms[2] = encode_ms[2] + (ccall("__w_clock_ms") - ft2)
    encode_ms[3] = encode_ms[3] + 1
  result

log_rope = Math.log(ROPE_BASE)
rope_power = ~2.0 / ROT_DIM
-> build_rope(pos)
  i = 0
  while i < ROT_HALF
    theta = Math.exp(log_rope * (~0.0 - i * rope_power))
    angle = pos * theta
    metal_buffer_write_f32(cos_tmp, i, Math.cos(angle))
    metal_buffer_write_f32(sin_tmp, i, Math.sin(angle))
    i = i + 1

-> dependency_barrier
  if concurrent then metal_batch_barrier(queue)

# Barrier on only the buffers that actually carry the RAW dependency. A full
# MTLBarrierScopeBuffers barrier drains EVERY outstanding write on the
# encoder (~1400 of them per token here); the 27B measured scoped barriers
# as most of the gap to the weight-streaming floor. FN_FULLBAR=1 restores
# full barriers so the change stays measurable.
scoped_barriers = ccall("__w_env", "FN_FULLBAR") != "1"
-> dep_on(bufs)
  if concurrent
    if scoped_barriers
      metal_batch_barrier_resources(queue, bufs)
    else
      metal_batch_barrier(queue)

# Matvec dispatch over an mv_tensor handle: NVFP4 triple when the selfquant
# sidecar carries the tensor, else bf16 (w2 wide kernel — 1.35-1.8x the naive
# one on every decode shape >=320 rows per autotune_qwen38fn.w; tiny-row
# matvecs a/b/inject/seg stay on the naive 1-row kernel).
-> enqueue_bf16(spec)
  h = spec[0]
  rows = spec[4]
  if h.size() == 3
    metal_dispatch_groups(queue, nvfp4_pipe, [h[0], h[1], spec[1], spec[2], spec[3], h[2]], rows / 8, 64)
  elsif rows >= 320
    metal_dispatch_groups(queue, bf16_w2_pipe, [h[0], spec[1], spec[2], spec[3], rows], (rows + 3) / 4, 64)
  else
    metal_dispatch_groups(queue, bf16_matvec_pipe, [h[0], spec[1], spec[2], spec[3]], rows, 32)

# Hyper-connection mix: fills n_tmp (normed stream) and xn (2560 block input),
# and precomputes inj_tmp for the paired combine.
-> hc_mix(hc)
  if skip_hc then return
  if hc_fused && hc[:down].size() == 3 && hc[:up].size() == 3 && hc[:inject] != nil
    # Deep-fused NVFP4 path: 2 serial stages instead of 5 (hc_fused.metal).
    metal_dispatch_groups(queue, hc_mix_a_pipe,
      [H, hc[:norm], hc[:down][0], hc[:down][1], hc[:down][2], hc[:inject],
       lowrank_tmp, inj_tmp, rms_tmp, EPS], (HC_LOWRANK + HC_COUNT + 1) / 2, 64)
    dep_on([lowrank_tmp, inj_tmp, rms_tmp])
    metal_dispatch_groups(queue, hc_mix_b_pipe,
      [H, hc[:norm], hc[:up][0], hc[:up][1], hc[:up][2], lowrank_tmp, rms_tmp, xn],
      HIDDEN / 256, 256)
    dep_on([xn, inj_tmp])
    return
  metal_dispatch_groups(queue, grms_pipe, [H, hc[:norm], n_tmp, HIDDEN, EPS], HC_COUNT, 256)
  dep_on([n_tmp])
  enqueue_bf16([hc[:down], n_tmp, lowrank_tmp, HC_HIDDEN, HC_LOWRANK])
  metal_dispatch_groups(queue, bf16_matvec_pipe, [hc[:inject], n_tmp, inj_tmp, HC_HIDDEN], HC_COUNT, 32)
  dep_on([lowrank_tmp])
  metal_dispatch_n(queue, silu_div_pipe, [lowrank_tmp, lowrank_tmp, ~0.0 + HC_COUNT, HC_LOWRANK], HC_LOWRANK)
  dep_on([lowrank_tmp])
  enqueue_bf16([hc[:up], lowrank_tmp, upraw_tmp, HC_LOWRANK, HC_HIDDEN])
  dep_on([upraw_tmp])
  metal_dispatch_n(queue, hc_mix_reduce_pipe, [upraw_tmp, n_tmp, xn, HC_COUNT, HIDDEN], HIDDEN)
  dep_on([xn, inj_tmp])

-> hc_combine
  if skip_hc then return
  metal_dispatch_n(queue, hc_combine_pipe, [H, y_tmp, inj_tmp, HC_COUNT, HIDDEN], HC_HIDDEN)
  dep_on([H])

# Final mixer: like hc_mix but with no inject and its own output slot.
-> mixer_collapse
  metal_dispatch_groups(queue, grms_pipe, [H, mixer[:norm], n_tmp, HIDDEN, EPS], HC_COUNT, 256)
  dep_on([n_tmp])
  enqueue_bf16([mixer[:down], n_tmp, lowrank_tmp, HC_HIDDEN, HC_LOWRANK])
  dep_on([lowrank_tmp])
  metal_dispatch_n(queue, silu_div_pipe, [lowrank_tmp, lowrank_tmp, ~0.0 + HC_COUNT, HC_LOWRANK], HC_LOWRANK)
  dep_on([lowrank_tmp])
  enqueue_bf16([mixer[:up], lowrank_tmp, upraw_tmp, HC_LOWRANK, HC_HIDDEN])
  dep_on([upraw_tmp])
  metal_dispatch_n(queue, hc_mix_reduce_pipe, [upraw_tmp, n_tmp, xn, HC_COUNT, HIDDEN], HIDDEN)
  dep_on([xn])

-> enqueue_ple(lyr)
  if skip_ple then return
  p = lyr[:ple]
  cs_in = p[:ping] == 0 ? p[:cs_a] : p[:cs_b]
  cs_out = p[:ping] == 0 ? p[:cs_b] : p[:cs_a]
  enqueue_bf16([p[:key], e_buf, ple_key_tmp, HIDDEN, HC_HIDDEN])
  enqueue_bf16([p[:value], e_buf, ple_v_tmp, HIDDEN, HIDDEN])
  metal_dispatch_groups(queue, grms_pipe, [H, p[:norm_query], ple_qn_tmp, HIDDEN, EPS], HC_COUNT, 256)
  dependency_barrier()
  metal_dispatch_groups(queue, grms_pipe, [ple_key_tmp, p[:norm_key], ple_kn_tmp, HIDDEN, EPS], HC_COUNT, 256)
  dependency_barrier()
  metal_dispatch_groups(queue, ple_gate_pipe, [ple_kn_tmp, ple_qn_tmp, ple_v_tmp, ple_gv_tmp, HIDDEN], HC_COUNT, 256)
  dependency_barrier()
  metal_dispatch_groups(queue, grms_pipe, [ple_gv_tmp, p[:norm_conv], ple_nc_tmp, HIDDEN, EPS], HC_COUNT, 256)
  dependency_barrier()
  metal_dispatch_n(queue, ple_conv_pipe, [p[:conv], cs_in, ple_nc_tmp, ple_gv_tmp, H, cs_out, HC_HIDDEN], HC_HIDDEN)
  dependency_barrier()
  p[:ping] = 1 - p[:ping]

-> enqueue_mamba(lyr)
  if skip_gdn then return
  cs_in = lyr[:ping] == 0 ? lyr[:cs_a] : lyr[:cs_b]
  cs_out = lyr[:ping] == 0 ? lyr[:cs_b] : lyr[:cs_a]
  ss_in = lyr[:ping] == 0 ? lyr[:ss_a] : lyr[:ss_b]
  ss_out = lyr[:ping] == 0 ? lyr[:ss_b] : lyr[:ss_a]
  enqueue_bf16([lyr[:qkv], xn, qkv_tmp, HIDDEN, QKV_DIM])
  enqueue_bf16([lyr[:z], xn, z_tmp, HIDDEN, V_DIM])
  metal_dispatch_groups(queue, bf16_matvec_pipe, [lyr[:a], xn, a_tmp, HIDDEN], HV, 32)
  metal_dispatch_groups(queue, bf16_matvec_pipe, [lyr[:b], xn, b_tmp, HIDDEN], HV, 32)
  dep_on([qkv_tmp])
  metal_dispatch_n(queue, conv_split_pipe, [lyr[:conv], cs_in, qkv_tmp, mq_tmp, mk_tmp, mv_tmp, cs_out, QKV_DIM, Q_DIM, K_DIM], QKV_DIM)
  dep_on([mq_tmp, mk_tmp, mv_tmp, a_tmp, b_tmp])
  # l2norm = rms*(1/sqrt(DK)) with the reference's eps INSIDE the sum:
  # rsqrt(sum + 1e-6) = (1/sqrt(DK)) * rsqrt(mean + 1e-6/DK), so the kernel's
  # mean-domain eps must be EPS/DK (plain EPS is a 128x overshoot that drifts
  # the recurrent state ~1e-3 by mid-stack).
  metal_dispatch_groups(queue, phn_pipe, [mq_tmp, q_norm_scale, DK, ~1.0 / DK, EPS / DK], HK, 32)
  metal_dispatch_groups(queue, phn_pipe, [mk_tmp, k_norm_scale, DK, ~1.0 / DK, EPS / DK], HK, 32)
  metal_dispatch_n(queue, g_beta_pipe, [a_tmp, b_tmp, lyr[:alog], lyr[:dtb], g_tmp, beta_tmp, HV], HV)
  dep_on([mq_tmp, mk_tmp, g_tmp, beta_tmp])
  metal_dispatch_3d(queue, delta_pipe, [mq_tmp, mk_tmp, mv_tmp, g_tmp, beta_tmp, ss_in, delta_tmp, ss_out, HK, HV, DK, DV], 1, DV / 4, HV, 32, 4, 1)
  dep_on([delta_tmp, z_tmp])
  metal_dispatch_groups(queue, rng_sig_pipe, [delta_tmp, z_tmp, lyr[:linear_norm], mamba_norm_tmp, DV, EPS], HV, 32)
  dep_on([mamba_norm_tmp])
  enqueue_bf16([lyr[:out], mamba_norm_tmp, y_tmp, V_DIM, HIDDEN])
  dep_on([y_tmp])
  lyr[:ping] = 1 - lyr[:ping]

-> enqueue_full(lyr, pos)
  if skip_attn then return
  enqueue_bf16([lyr[:q], xn, qfull_tmp, HIDDEN, QFULL_DIM])
  enqueue_bf16([lyr[:k], xn, k_tmp, HIDDEN, KV_DIM])
  enqueue_bf16([lyr[:v], xn, v_tmp, HIDDEN, KV_DIM])
  dep_on([qfull_tmp])
  metal_dispatch_n(queue, split_pipe, [qfull_tmp, queries_tmp, attn_gate_tmp, N_HEADS, HEAD_DIM], ATTN_DIM)
  dep_on([queries_tmp, k_tmp])
  metal_dispatch_groups(queue, phn_pipe, [queries_tmp, lyr[:qn], HEAD_DIM, ~1.0 / HEAD_DIM, EPS], N_HEADS, 32)
  metal_dispatch_groups(queue, phn_pipe, [k_tmp, lyr[:kn], HEAD_DIM, ~1.0 / HEAD_DIM, EPS], N_KV_HEADS, 32)
  dep_on([queries_tmp, k_tmp])
  if pos > 0
    metal_dispatch_n(queue, rope_pipe, [queries_tmp, cos_tmp, sin_tmp, HEAD_DIM, ROT_HALF, N_HEADS], N_HEADS * ROT_HALF)
    metal_dispatch_n(queue, rope_pipe, [k_tmp, cos_tmp, sin_tmp, HEAD_DIM, ROT_HALF, N_KV_HEADS], N_KV_HEADS * ROT_HALF)
  dep_on([queries_tmp, k_tmp, v_tmp])
  metal_dispatch_n(queue, kv_write_pipe, [k_tmp, lyr[:k_cache], pos, KV_DIM], KV_DIM)
  metal_dispatch_n(queue, kv_write_pipe, [v_tmp, lyr[:v_cache], pos, KV_DIM], KV_DIM)
  dep_on([lyr[:k_cache], lyr[:v_cache]])
  metal_dispatch_groups(queue, sdpa_pipe, [queries_tmp, lyr[:k_cache], lyr[:v_cache], attn_tmp, GQA, pos + 1, HEAD_DIM, KV_DIM, ATTN_SCALE], N_HEADS, 256)
  dep_on([attn_tmp, attn_gate_tmp])
  metal_dispatch_n(queue, gate_pipe, [attn_tmp, attn_gate_tmp, ATTN_DIM], ATTN_DIM)
  dep_on([attn_tmp])
  enqueue_bf16([lyr[:out], attn_tmp, y_tmp, ATTN_DIM, HIDDEN])
  dep_on([y_tmp])

-> enqueue_gather(spec)
  ex = spec[0]
  offs = spec[1]
  input = spec[2]
  output = spec[3]
  kdim = spec[4]
  rows = spec[5]
  x_stride = spec[6]
  q = ex[:quarters]
  metal_dispatch_groups(queue, gather_pipe,
    [q[0], q[1], q[2], q[3], top_idx, ex[:slot_map], input, output,
     kdim, rows, offs[0], offs[1], offs[2], offs[3], offs[4], offs[5], x_stride,
     ex[:hot], offs[6], offs[7], offs[8]],
    TOP_K * (rows / 8), 64)

-> enqueue_moe(spec2)
  lyr = spec2[0]
  li = spec2[1]
  ex = lyr[:experts]
  enqueue_bf16([lyr[:router], xn, router_logits, HIDDEN, N_EXPERTS])
  if !skip_shared
    enqueue_bf16([lyr[:sh_gate], xn, sg_tmp, HIDDEN, SHARED_FFN])
    enqueue_bf16([lyr[:sh_up], xn, su_tmp, HIDDEN, SHARED_FFN])
    metal_dispatch_groups(queue, bf16_matvec_pipe, [lyr[:sh_seg], xn, seg_tmp, HIDDEN], 1, 32)
  dep_on([router_logits, sg_tmp, su_tmp])
  metal_dispatch_groups(queue, router_pipe, [router_logits, top_idx, top_w], 1, 512)
  if !skip_shared
    metal_dispatch_n(queue, silu_pipe, [sg_tmp, su_tmp, sh_tmp, SHARED_FFN], SHARED_FFN)
  dep_on([top_idx, sh_tmp])
  if expert_hist
    metal_dispatch_n(queue, expert_hist_pipe, [top_idx, hist_buf, li, TOP_K], TOP_K)
  if !skip_moe
    enqueue_gather([ex, ex[:offs]["gate_proj"], xn, eg_tmp, HIDDEN, MOE_FFN, 0])
    enqueue_gather([ex, ex[:offs]["up_proj"], xn, eu_tmp, HIDDEN, MOE_FFN, 0])
  if !skip_shared
    enqueue_bf16([lyr[:sh_down], sh_tmp, shared_tmp, SHARED_FFN, HIDDEN])
  dep_on([eg_tmp, eu_tmp])
  if !skip_moe
    metal_dispatch_n(queue, silu_pipe, [eg_tmp, eu_tmp, eh_tmp, TOP_K * MOE_FFN], TOP_K * MOE_FFN)
    dep_on([eh_tmp])
    enqueue_gather([ex, ex[:offs]["down_proj"], eh_tmp, ed_tmp, MOE_FFN, HIDDEN, MOE_FFN])
  dep_on([ed_tmp, top_w, shared_tmp, seg_tmp])
  metal_dispatch_n(queue, moe_output_pipe, [ed_tmp, top_w, shared_tmp, seg_tmp, y_tmp, TOP_K, HIDDEN], HIDDEN)
  dep_on([y_tmp])

-> enqueue_argmax
  metal_dispatch_groups(queue, argmax_stage1_pipe,
    [logits, argmax_partial_values, argmax_partial_indices, N_VOCAB, ARGMAX_CHUNKS, 1], ARGMAX_CHUNKS, 256)
  dependency_barrier()
  metal_dispatch_groups(queue, argmax_stage2_pipe,
    [argmax_partial_values, argmax_partial_indices, argmax_out, ARGMAX_CHUNKS, 1], 1, 256)

fn_time = ccall("__w_env", "FN_TIME") == "1"
encode_ms = [~0.0, ~0.0, ~0.0, 0]
# The prebuilt-program path handles the plain benchmark/generation config;
# golden dumps, ablation, and expert-hist keep the original per-call path.
fast_path = golden_prefix == "" && !expert_hist && skip_spec == "" && !hc_fused

-> forward_fast(token_id, pos)
  ft0 = fn_time ? ccall("__w_clock_ms") : ~0.0
  build_rope(pos)
  ple_gather([token_id, e_buf])
  metal_buffer_write_i32(tok_buf, 0, token_id)
  metal_buffer_write_i32(pos_buf, 0, pos)
  metal_buffer_write_i32(pos1_buf, 0, pos + 1)
  ft1 = fn_time ? ccall("__w_clock_ms") : ~0.0
  metal_batch_begin_concurrent(queue)
  metal_dispatch_n(queue, bf16_embed_pipe, embed_args, HIDDEN)
  metal_batch_barrier_resources(queue, [h_embed])
  s = 0
  while s < HC_COUNT
    metal_dispatch_n(queue, copy_at_pipe, [h_embed, H, 0, s * HIDDEN, HIDDEN], HIDDEN)
    s = s + 1
  metal_batch_barrier_resources(queue, [H])
  li = 0
  while li < N_LAYERS
    lyr = layers[li]
    if lyr[:ple] != nil
      run_prog(lyr[:ple][:ping] == 0 ? lyr[:ple_prog_a] : lyr[:ple_prog_b])
      lyr[:ple][:ping] = 1 - lyr[:ple][:ping]
    run_prog(lyr[:ping] == 0 || lyr[:kind] == "full" ? lyr[:prog_a] : lyr[:prog_b])
    if lyr[:kind] == "mamba" then lyr[:ping] = 1 - lyr[:ping]
    if li == 15 || li == 31
      metal_batch_commit(queue)
      metal_batch_begin_concurrent(queue)
    li = li + 1
  run_prog(head_prog)
  ft2 = fn_time ? ccall("__w_clock_ms") : ~0.0
  metal_batch_commit(queue)
  ple_advance(token_id)
  result = metal_buffer_read_i32(argmax_out, 0)
  if fn_time
    encode_ms[0] = encode_ms[0] + (ft1 - ft0)
    encode_ms[1] = encode_ms[1] + (ft2 - ft1)
    encode_ms[2] = encode_ms[2] + (ccall("__w_clock_ms") - ft2)
    encode_ms[3] = encode_ms[3] + 1
  result

-> forward(token_id, pos, want_logits)
  if fast_path && concurrent && use_icb then return forward_icb(token_id, pos)
  if fast_path && concurrent then return forward_fast(token_id, pos)
  ft0 = fn_time ? ccall("__w_clock_ms") : ~0.0
  if pos > 0 then build_rope(pos)
  ple_gather([token_id, e_buf])
  ft1 = fn_time ? ccall("__w_clock_ms") : ~0.0
  if concurrent then metal_batch_begin_concurrent(queue) else metal_batch_begin(queue)
  metal_dispatch_n(queue, bf16_embed_pipe, [embed_w, h_embed, token_id, HIDDEN], HIDDEN)
  dependency_barrier()
  s = 0
  while s < HC_COUNT
    metal_dispatch_n(queue, copy_at_pipe, [h_embed, H, 0, s * HIDDEN, HIDDEN], HIDDEN)
    s = s + 1
  dependency_barrier()
  if !concurrent then metal_batch_commit(queue)

  dbg = golden_prefix != "" && want_logits
  li = 0
  while li < N_LAYERS
    if !concurrent then metal_batch_begin(queue)
    lyr = layers[li]
    if lyr[:ple] != nil
      enqueue_ple(lyr)
      if dbg
        metal_dispatch_n(queue, copy_at_pipe, [e_buf, dbg_taps, 0, 8 * HC_HIDDEN, HIDDEN], HIDDEN)
        metal_dispatch_n(queue, copy_at_pipe, [ple_qn_tmp, dbg_taps, 0, 9 * HC_HIDDEN, HC_HIDDEN], HC_HIDDEN)
        metal_dispatch_n(queue, copy_at_pipe, [ple_gv_tmp, dbg_taps, 0, 10 * HC_HIDDEN, HC_HIDDEN], HC_HIDDEN)
        metal_dispatch_n(queue, copy_at_pipe, [H, dbg_taps, 0, 11 * HC_HIDDEN, HC_HIDDEN], HC_HIDDEN)
    if dbg && li == 0
      metal_dispatch_n(queue, copy_at_pipe, [h_embed, dbg_taps, 0, 0, HIDDEN], HIDDEN)
      metal_dispatch_n(queue, copy_at_pipe, [H, dbg_taps, 0, HC_HIDDEN, HC_HIDDEN], HC_HIDDEN)
    hc_mix(lyr[:attn_hc])
    if dbg && li == 0
      metal_dispatch_n(queue, copy_at_pipe, [n_tmp, dbg_taps, 0, 2 * HC_HIDDEN, HC_HIDDEN], HC_HIDDEN)
      metal_dispatch_n(queue, copy_at_pipe, [xn, dbg_taps, 0, 3 * HC_HIDDEN, HIDDEN], HIDDEN)
    if lyr[:kind] == "mamba" then enqueue_mamba(lyr) else enqueue_full(lyr, pos)
    if dbg && li == 0
      metal_dispatch_n(queue, copy_at_pipe, [y_tmp, dbg_taps, 0, 4 * HC_HIDDEN, HIDDEN], HIDDEN)
    hc_combine()
    if dbg && li == 0
      metal_dispatch_n(queue, copy_at_pipe, [H, dbg_taps, 0, 5 * HC_HIDDEN, HC_HIDDEN], HC_HIDDEN)
    hc_mix(lyr[:mlp_hc])
    if dbg && li == 0
      metal_dispatch_n(queue, copy_at_pipe, [xn, dbg_taps, 0, 6 * HC_HIDDEN, HIDDEN], HIDDEN)
    enqueue_moe([lyr, li])
    if dbg && li == 0
      metal_dispatch_n(queue, copy_at_pipe, [y_tmp, dbg_taps, 0, 7 * HC_HIDDEN, HIDDEN], HIDDEN)
    hc_combine()
    if dbg
      metal_dispatch_n(queue, copy_at_pipe, [H, golden_taps, 0, li * HC_HIDDEN, HC_HIDDEN], HC_HIDDEN)
    if !concurrent then metal_batch_commit(queue)
    if concurrent && (li == 15 || li == 31)
      metal_batch_commit(queue)
      metal_batch_begin_concurrent(queue)
    li = li + 1

  if !concurrent then metal_batch_begin(queue)
  result = -1
  if want_logits && !skip_head
    mixer_collapse()
    enqueue_bf16([lm_head, xn, logits, HIDDEN, N_VOCAB])
    dependency_barrier()
    enqueue_argmax()
  ft2 = fn_time ? ccall("__w_clock_ms") : ~0.0
  metal_batch_commit(queue)
  ple_advance(token_id)
  if want_logits then result = metal_buffer_read_i32(argmax_out, 0)
  if fn_time
    encode_ms[0] = encode_ms[0] + (ft1 - ft0)
    encode_ms[1] = encode_ms[1] + (ft2 - ft1)
    encode_ms[2] = encode_ms[2] + (ccall("__w_clock_ms") - ft2)
    encode_ms[3] = encode_ms[3] + 1
  result

golden_taps = nil
dbg_taps = nil
if golden_prefix != ""
  golden_taps = metal_buffer(device, N_LAYERS * HC_HIDDEN * 4)
  dbg_taps = metal_buffer(device, 12 * HC_HIDDEN * 4)

# ---- prompt ----
prompt_seed = [760, 6511, 314, 9338, 369]
prompt = []
i = 0
if prompt_ids_file != ""
  prompt = JSON.parse(read_file(prompt_ids_file))
  if prompt.size() + n_generate > MAX_POS
    raise "prompt file " + prompt.size().to_s + " + generate " + n_generate.to_s + " exceeds MAX_POS " + MAX_POS.to_s
elsif prompt_tokens <= prompt_seed.size()
  while i < prompt_tokens
    prompt.push(prompt_seed[i])
    i = i + 1
else
  raise "long prompts need a prompt ids file (tokenizer prose fixture not wired yet)"

setup_elapsed = ccall("__w_clock_ms") - setup_t0
<< "setup " + setup_elapsed.to_s + " ms; prefill " + prompt.size().to_s + " tokens"
prefill_t0 = ccall("__w_clock_ms")
pred = -1
i = 0
while i < prompt.size()
  pred = forward(prompt[i], i, i == prompt.size() - 1)
  i = i + 1
if ccall("__w_env", "FN_DUMP_H") != nil && ccall("__w_env", "FN_DUMP_H") != ""
  File.write_bytes(ccall("__w_env", "FN_DUMP_H"), metal_buffer_view(H, 8, HC_HIDDEN * 4))
  File.write_bytes(ccall("__w_env", "FN_DUMP_H") + ".logits", metal_buffer_view(logits, 8, N_VOCAB * 4))
  File.write_bytes(ccall("__w_env", "FN_DUMP_H") + ".cs_a", metal_buffer_view(layers[0][:cs_a], 8, 3 * QKV_DIM * 4))
  File.write_bytes(ccall("__w_env", "FN_DUMP_H") + ".cs_b", metal_buffer_view(layers[0][:cs_b], 8, 3 * QKV_DIM * 4))
  File.write_bytes(ccall("__w_env", "FN_DUMP_H") + ".kc", metal_buffer_view(layers[3][:k_cache], 8, 4 * KV_DIM * 4))
  File.write_bytes(ccall("__w_env", "FN_DUMP_H") + ".ss_a", metal_buffer_view(layers[0][:ss_a], 8, 1024 * 4))
  File.write_bytes(ccall("__w_env", "FN_DUMP_H") + ".ss_b", metal_buffer_view(layers[0][:ss_b], 8, 1024 * 4))
prefill_elapsed = ccall("__w_clock_ms") - prefill_t0
encode_ms[0] = ~0.0
encode_ms[1] = ~0.0
encode_ms[2] = ~0.0
encode_ms[3] = 0
<< "prefill " + prefill_elapsed.to_s + " ms; first prediction " + pred.to_s

if golden_prefix != ""
  # Dump per-layer H (post-layer, last prompt position) + logits for diffing
  # against flash_next_ref.py --dump.
  File.write_bytes(golden_prefix + "_h.f32", metal_buffer_view(golden_taps, 8, N_LAYERS * HC_HIDDEN * 4))
  File.write_bytes(golden_prefix + "_logits.f32", metal_buffer_view(logits, 8, N_VOCAB * 4))
  File.write_bytes(golden_prefix + "_dbg.f32", metal_buffer_view(dbg_taps, 8, 12 * HC_HIDDEN * 4))
  << "goldens -> " + golden_prefix + "_{h,logits,dbg}.f32"

ids = []
ids.push(pred)
pos = prompt.size()
t0 = ccall("__w_clock_ms")
round_ms = []
while ids.size() < n_generate
  rt0 = ccall("__w_clock_ms")
  pred = forward(pred, pos, true)
  ids.push(pred)
  pos = pos + 1
  round_ms.push(ccall("__w_clock_ms") - rt0)
elapsed = ccall("__w_clock_ms") - t0
decoded = ids.size() - 1
sorted_ms = round_ms.sort()
median_ms = sorted_ms.size() > 0 ? sorted_ms[sorted_ms.size() / 2] : ~0.0
tokenizer = Tungsten:Llama:Tokenizer.from_packed_tokenizer(TOKENIZER_BIN)
<< "ids: " + ids.to_s
<< "text: " + tokenizer.decode(ids)
if expert_hist
  File.write_bytes("/tmp/fn_expert_hist.u32", metal_buffer_view(hist_buf, 8, N_LAYERS * N_EXPERTS * 4))
  << "expert histogram -> /tmp/fn_expert_hist.u32"
if fn_time && encode_ms[3] > 0
  n = ~0.0 + encode_ms[3]
  << "host phases/round: rope+ple " + (encode_ms[0] / n).to_s + " ms, encode " + (encode_ms[1] / n).to_s + " ms, commit+wait+read " + (encode_ms[2] / n).to_s + " ms"
if decoded > 0
  << "decode: " + decoded.to_s + " tokens in " + elapsed.to_s + " ms = " + (1000.0 * decoded / elapsed).to_s + " tok/s (median round " + median_ms.to_s + " ms)"
