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
# Dense-exact boundary is 2051 (QSA budget 2048 + max tail 3). FN_CTX raises
# the context (kv/index caches sized accordingly, cap 262144 = config
# max_position_embeddings); positions beyond 2051 attend through the QSA
# lightning indexer. FN_QSA=1 forces the indexer from position 0 (the
# equivalence gate: below the boundary selection covers everything and the
# selected-order SDPA is arithmetically identical to dense).
MAX_POS = 2051
fn_ctx_env = ccall("__w_env", "FN_CTX")
if fn_ctx_env != nil && fn_ctx_env != ""
  MAX_POS = fn_ctx_env.to_i()
  if MAX_POS > 262144 then MAX_POS = 262144
  if MAX_POS < 64 then MAX_POS = 64
qsa_on = MAX_POS > 2051 || ccall("__w_env", "FN_QSA") == "1"
QSA_MAXB = MAX_POS / 4 + 1
QSA_SEL_STRIDE = 512 * 4 + 3
IDX_DIM = 640

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
# FN_RUNG: "1" = both autotuned rungs, "b1" / "16r" = just that one,
# "0"/unset = plain 8-row kernel everywhere. Rungs are ids-identical.
fn_rung = env("FN_RUNG")
use_b1 = fn_rung == "1" || fn_rung == "b1"
use_16r = fn_rung == "1" || fn_rung == "16r"
expert_hist = ARGV.size() > 5 && ARGV[5] == "expert-hist"
# "pin:<N>" wires the per-layer top-N experts (by /tmp/fn_expert_hist.u32 from
# an expert-hist run) into a private hot overlay the gather kernel prefers.
pin_count = 0
if ARGV.size() > 5 && ARGV[5].size() > 4 && ARGV[5].slice(0, 4) == "pin:"
  pin_count = ARGV[5].slice(4, ARGV[5].size() - 4).to_i()
if pin_count > 512 then raise "pin count must be <= 512"
# "multi:<N>" (N 1..8): after the serial decode produces its ids (the oracle),
# reset all recurrent state, re-run the prefill, then re-decode the same
# tokens in width-N blocks through the fn_multi/decode_multi kernel families
# and demand EXACT id agreement at every position. Foundation for MTP verify.
# Forces the per-call serial path (host rope) and naive bf16 matvecs so the
# serial and multi arms share summation order everywhere.
multi_n = 0
if ARGV.size() > 5 && ARGV[5].size() > 6 && ARGV[5].slice(0, 6) == "multi:"
  multi_n = ARGV[5].slice(6, ARGV[5].size() - 6).to_i()
if multi_n > 8 then raise "multi width must be <= 8"
# "mtp:<D>": speculative decode — draft D tokens with the MTP head each
# round, verify the block width-(D+1) via forward_multi, accept the longest
# matching prefix, tape-replay the recurrent states for partial accepts.
mtp_spec = 0
mtp_adaptive = 0
if ARGV.size() > 5 && ARGV[5] == "mtp:adaptive"
  # depth self-tunes on acceptance: full accept raises it (cap 7), a miss
  # drops it to what actually stuck
  mtp_adaptive = 1
  mtp_spec = 3
elsif ARGV.size() > 5 && ARGV[5].size() > 4 && ARGV[5].slice(0, 4) == "mtp:"
  mtp_spec = ARGV[5].slice(4, ARGV[5].size() - 4).to_i()
if mtp_spec > 7 then raise "mtp draft depth must be <= 7"
mtp_d_cur = [mtp_spec]
mtp_streak = [0]
naive_mv = multi_n > 0
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
skip_hcmv = skip_spec.include?("hcmv")
skip_moegemm = skip_spec.include?("moegemm")
skip_moestage = skip_spec.include?("moestage")
skip_moeshared = skip_spec.include?("moeshared")
skip_hcbar = skip_spec.include?("hcbar")
if skip_spec != "" then << "ABLATION: skipping " + skip_spec + " — output is garbage, timing only"
# FN_HCFUSED=1: 2-stage fused HC mix. Measured 2ms SLOWER than the 5-stage
# path (the concurrent encoder already overlaps those stages) — kept only
# so the negative result stays reproducible.
hc_fused = ccall("__w_env", "FN_HCFUSED") == "1"
# FN_CPROG=0: run prebuilt programs through the .w dispatch loop instead of
# the C-side executor (w_metal_program_run) — A/B escape; commands identical.
cprog = ccall("__w_env", "FN_CPROG") != "0"
# FN_MTP=1: load the MTP head and measure draft acceptance during decode
# (each round drafts the NEXT-next token; the following round scores it).
mtp_depth = 0
if ccall("__w_env", "FN_MTP") != nil && ccall("__w_env", "FN_MTP") != ""
  mtp_depth = ccall("__w_env", "FN_MTP").to_i()
if mtp_spec > 0 then mtp_depth = mtp_spec
if qsa_on && (mode != "concurrent" || golden_prefix != "" || expert_hist || skip_spec != "" || hc_fused)
  raise "QSA (FN_CTX > 2051 or FN_QSA=1) requires the concurrent fast path"
if MAX_POS > 2051 && (multi_n > 0 || mtp_spec > 0)
  raise "multi/mtp modes beyond ctx 2051 need the QSA multi path (not yet wired)"

mtp_pending = [0 - 1]
mtp_hits = [0]
mtp_total = [0]
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
# Rung winners from autotune_qwen38fn.w nv: the 8-row default starves shapes
# with few output rows (too few TGs to fill the GPU) — b1r1 (2 rows/TG) wins
# +46-52% at rows<=640; 16r wins +19% on the 2560x6144 out-projections.
# Per-row summation order is identical across the family (ids-identical).
nvfp4_16r_pipe = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_scaled_rows.metal")), "nvfp4_matvec_mlx_scaled_16r")
nvfp4_b1r1_pipe = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_scaled_wide.metal")), "nvfp4_wide_b1_r1")
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
ple_gpu_lib = metal_compile_source(device, read_file(FN_DIR + "ple_gather_gpu.metal"))
rope_tab_pipe = metal_pipeline(ple_gpu_lib, "build_rope_tab")
# f64 copy of log(rope base) — the Decimal log_rope can't autobox into a
# kernel argument
qsa_logb = Math.log(~0.0 + ROPE_BASE)
qsa_lib = metal_compile_source(device, read_file(FN_DIR + "qsa.metal"))
qsa_kw_pipe = metal_pipeline(qsa_lib, "qsa_k_write")
qsa_build_pipe = metal_pipeline(qsa_lib, "qsa_build_blocks")
qsa_scores_pipe = metal_pipeline(qsa_lib, "qsa_scores")
qsa_select_pipe = metal_pipeline(qsa_lib, "qsa_select")
qsa_sdpa_pipe = metal_pipeline(qsa_lib, "qsa_sdpa_selected")
ple_gather_pipe = metal_pipeline(ple_gpu_lib, "ple_table_gather")
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
    # h[3] = the ORIGINAL bf16 weight: chunked prefill GEMMs read it instead
    # of the sidecar (no nibble decode; 2x bytes amortize across the chunk)
    [sq_tensor(name), sq_tensor(name + ".scale"), sq_tensor(name + ".global_scale"), raw_tensor(name)]
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
    if qsa_on
      iqn = metal_buffer(device, 128 * 4)
      ikn = metal_buffer(device, 128 * 4)
      load_shifted_norm([prefix + "self_attn.indexer.q_layernorm.weight", 128, iqn])
      load_shifted_norm([prefix + "self_attn.indexer.k_layernorm.weight", 128, ikn])
      base[:idx_qk] = mv_tensor(prefix + "self_attn.indexer.index_qk_proj.weight")
      base[:idx_qn] = iqn
      base[:idx_kn] = ikn
      base[:idx_kc] = metal_buffer(device, MAX_POS * 128 * 4)
      base[:idx_blk] = metal_buffer(device, QSA_MAXB * 128 * 4)
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
ple_bulk = ccall("__w_env", "FN_PLE_SCALAR") != "1"
ple_gather_mmaps = []
ple_gather_offsets = []
h = 0
while h < 16
  ple_gather_mmaps.push(nil)
  ple_gather_offsets.push(0)
  h = h + 1

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
  dst_base = spec.size() > 2 ? spec[2] : 0
  use_bulk = ple_bulk && dst_base == 0
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
    if use_bulk
      ple_gather_mmaps[h] = m
      ple_gather_offsets[h] = off
    else
      j = 0
      while j < ple_head_dim
        metal_buffer_write_f32(dst, dst_base + h * ple_head_dim + j, ple_e4m3[m.byte_at(off + j)] * ple_scale)
        j = j + 1
    h = h + 1
  if use_bulk
    metal_fp8_e4m3_gather_rows(dst, ple_gather_mmaps, ple_gather_offsets, ple_head_dim, ple_scale)

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
pending_cbs = []
idx_qk_tmp = metal_buffer(device, IDX_DIM * 4)
idx_q_tmp = metal_buffer(device, 512 * 4)
qsa_scores_buf = metal_buffer(device, QSA_MAXB * 4)
qsa_sel_buf = metal_buffer(device, QSA_SEL_STRIDE * 4)
qsa_ns_buf = metal_buffer(device, 4)
qsa_nb_buf = metal_buffer(device, 4)
qsa_vis_buf = metal_buffer(device, 4)
qsa_range_buf = metal_buffer(device, 8)
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
  if h.size() >= 3
    if use_b1 && rows <= 640
      prog.push([0, nvfp4_b1r1_pipe, [h[0], h[1], input, output, kdim, rows, h[2]], (rows + 1) / 2, 64])
    elsif use_16r && rows == 2560 && kdim >= 6144
      prog.push([0, nvfp4_16r_pipe, [h[0], h[1], input, output, kdim, h[2]], rows / 16, 128])
    else
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
  prog.push([3, delta_pipe, [mq_tmp, mk_tmp, mv_tmp, g_tmp, beta_tmp, ss_in, delta_tmp, ss_out, HK, HV, DK, DV], [1, DV / 4, HV, 32, 4, 1], 0])
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
  if qsa_on
    # lightning indexer: proj -> split -> q norm+rope / raw-k cache -> pooled
    # block build -> relu-sum scores -> top-512 blocks + tail -> selected SDPA.
    # All grids fixed; bounds (nb/vis/range) are host-written buffers.
    prog_mv([prog, lyr[:idx_qk], xn, idx_qk_tmp, HIDDEN, IDX_DIM])
    prog.push([1, nil, [idx_qk_tmp], 0, 0])
    prog.push([2, copy_at_pipe, [idx_qk_tmp, idx_q_tmp, 0, 0, 512], 512, 0])
    prog.push([2, qsa_kw_pipe, [idx_qk_tmp, lyr[:idx_kc], pos_buf, 1], 128, 0])
    prog.push([1, nil, [idx_q_tmp, lyr[:idx_kc]], 0, 0])
    prog.push([0, phn_pipe, [idx_q_tmp, lyr[:idx_qn], 128, ~1.0 / 128, EPS], 4, 32])
    prog.push([0, qsa_build_pipe, [lyr[:idx_kc], lyr[:idx_kn], lyr[:idx_blk], qsa_range_buf, EPS, qsa_logb], 1, 128])
    prog.push([1, nil, [idx_q_tmp], 0, 0])
    prog.push([2, rope_pipe, [idx_q_tmp, cos_tmp, sin_tmp, 128, ROT_HALF, 4], 4 * ROT_HALF, 0])
    prog.push([1, nil, [idx_q_tmp, lyr[:idx_blk]], 0, 0])
    prog.push([0, qsa_scores_pipe, [idx_q_tmp, lyr[:idx_blk], qsa_scores_buf, qsa_nb_buf, QSA_MAXB, 1], (QSA_MAXB + 255) / 256, 256])
    prog.push([1, nil, [qsa_scores_buf], 0, 0])
    prog.push([0, qsa_select_pipe, [qsa_scores_buf, qsa_nb_buf, qsa_vis_buf, qsa_sel_buf, qsa_ns_buf, QSA_MAXB, 512], 1, 512])
    prog.push([1, nil, [qsa_sel_buf, qsa_ns_buf], 0, 0])
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
  if qsa_on
    prog.push([0, qsa_sdpa_pipe, [queries_tmp, lyr[:k_cache], lyr[:v_cache], attn_tmp, qsa_sel_buf, qsa_ns_buf, GQA, N_HEADS, KV_DIM, ATTN_SCALE, QSA_SEL_STRIDE, 1], N_HEADS, 256])
  else
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
  if cprog
    # C-side executor: one bridge crossing for the whole program; emits
    # byte-identical encoder commands to the per-call loop below.
    ccall("w_metal_program_run", queue, prog, concurrent ? 1 : 0)
    return
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
      d3 = st[3]
      metal_dispatch_3d(queue, st[1], st[2], d3[0], d3[1], d3[2], d3[3], d3[4], d3[5])
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
    d3 = st[3]
    metal_icb_add_3d(bstate[0], st[1], icb_args(st[2]), d3[0], d3[1], d3[2], d3[3], d3[4], d3[5])
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
    metal_icb_add(bstate[0], rope_tab_pipe, icb_args([pos_buf, cos_tmp, sin_tmp, log_rope, ROT_HALF]), 1, 32)
    metal_icb_add(bstate[0], bf16_embed_pipe, icb_args(embed_args), HIDDEN / 256, 256)
    bstate[1] = 2
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
  ple_gather([token_id, e_buf])
  metal_buffer_write_i32(tok_buf, 0, token_id)
  metal_buffer_write_i32(pos_buf, 0, pos)
  metal_buffer_write_i32(pos1_buf, 0, pos + 1)
  if qsa_on
    metal_buffer_write_i32(qsa_nb_buf, 0, (pos + 1) / 4)
    metal_buffer_write_i32(qsa_vis_buf, 0, pos + 1)
    if (pos + 1) % 4 == 0
      metal_buffer_write_i32(qsa_range_buf, 0, (pos + 1) / 4 - 1)
      metal_buffer_write_i32(qsa_range_buf, 1, (pos + 1) / 4)
    else
      metal_buffer_write_i32(qsa_range_buf, 0, 0)
      metal_buffer_write_i32(qsa_range_buf, 1, 0)
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
  if h.size() >= 3
    # same rung selection as prog_mv — keep the two paths ids-identical
    if use_b1 && rows <= 640
      metal_dispatch_groups(queue, nvfp4_b1r1_pipe, [h[0], h[1], spec[1], spec[2], spec[3], rows, h[2]], (rows + 1) / 2, 64)
    elsif use_16r && rows == 2560 && spec[3] >= 6144
      metal_dispatch_groups(queue, nvfp4_16r_pipe, [h[0], h[1], spec[1], spec[2], spec[3], h[2]], rows / 16, 128)
    else
      metal_dispatch_groups(queue, nvfp4_pipe, [h[0], h[1], spec[1], spec[2], spec[3], h[2]], rows / 8, 64)
  elsif rows >= 320 && !naive_mv
    metal_dispatch_groups(queue, bf16_w2_pipe, [h[0], spec[1], spec[2], spec[3], rows], (rows + 3) / 4, 64)
  else
    metal_dispatch_groups(queue, bf16_matvec_pipe, [h[0], spec[1], spec[2], spec[3]], rows, 32)

# Hyper-connection mix: fills n_tmp (normed stream) and xn (2560 block input),
# and precomputes inj_tmp for the paired combine.
-> hc_mix(hc)
  if skip_hc then return
  if hc_fused && hc[:down].size() >= 3 && hc[:up].size() >= 3 && hc[:inject] != nil
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
fast_path = golden_prefix == "" && !expert_hist && skip_spec == "" && !hc_fused && multi_n == 0

-> forward_fast(token_id, pos)
  ft0 = fn_time ? ccall("__w_clock_ms") : ~0.0
  ple_gather([token_id, e_buf])
  metal_buffer_write_i32(tok_buf, 0, token_id)
  metal_buffer_write_i32(pos_buf, 0, pos)
  metal_buffer_write_i32(pos1_buf, 0, pos + 1)
  if qsa_on
    metal_buffer_write_i32(qsa_nb_buf, 0, (pos + 1) / 4)
    metal_buffer_write_i32(qsa_vis_buf, 0, pos + 1)
    if (pos + 1) % 4 == 0
      metal_buffer_write_i32(qsa_range_buf, 0, (pos + 1) / 4 - 1)
      metal_buffer_write_i32(qsa_range_buf, 1, (pos + 1) / 4)
    else
      metal_buffer_write_i32(qsa_range_buf, 0, 0)
      metal_buffer_write_i32(qsa_range_buf, 1, 0)
  ft1 = fn_time ? ccall("__w_clock_ms") : ~0.0
  metal_batch_begin_concurrent(queue)
  metal_dispatch_groups(queue, rope_tab_pipe, [pos_buf, cos_tmp, sin_tmp, log_rope, ROT_HALF], 1, 32)
  metal_dispatch_n(queue, bf16_embed_pipe, embed_args, HIDDEN)
  metal_batch_barrier_resources(queue, [h_embed, cos_tmp, sin_tmp])
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
      # commit WITHOUT waiting: the chunk executes while later layers encode.
      # Buffers on one queue execute in commit order, so the final commit's
      # wait transitively covers these; the deferred waits are then instant
      # and only release the handles.
      pending_cbs.push(metal_batch_commit_async(queue))
      metal_batch_begin_concurrent(queue)
    li = li + 1
  run_prog(head_prog)
  ft2 = fn_time ? ccall("__w_clock_ms") : ~0.0
  metal_batch_commit(queue)
  while pending_cbs.size() > 0
    metal_command_buffer_wait(pending_cbs.pop())
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

# ---- width-n multi verify (multi:N mode) ---------------------------------
# Token-major layout: every per-token tensor T of width W becomes [n, W].
# All multi kernels are expression-level clones of the serial ones (audited:
# router/gather/hc/ple/grms are structural clones in fn_multi.metal; the 27B
# decode_multi family matches our serial kernels except per-head norm, which
# fn_phn_rope_multi re-clones with 1/sqrt and (x*rrms)*w). GDN conv/delta
# advance their recurrent state by n tokens with ONE ping flip per block.
# 64 = the prefill chunk width; spec/multi verify widths stay <= 8 (rung
# kernels), widths 9..64 route to the nvfp4_gemm_f32 m-tiles.
MULTI_MAX = 512
PREFILL_CHUNK = 512
# only the final chunk needs logits; cap it so logits_m stays 64-wide
PREFILL_LAST_MAX = 64
if multi_n > 0 || mtp_depth > 0 || prompt_tokens > 8 || prompt_ids_file != ""
  fnm_lib = metal_compile_source(device, read_file(FN_DIR + "fn_multi.metal"))
  grms_m_pipe = metal_pipeline(fnm_lib, "grouped_rms_norm_multi")
  hc_mix_reduce_m_pipe = metal_pipeline(fnm_lib, "hc_mix_reduce_multi")
  hc_combine_m_pipe = metal_pipeline(fnm_lib, "hc_combine_multi")
  router_m_pipe = metal_pipeline(fnm_lib, "router_softmax_topk10_multi")
  gather_m_pipe = metal_pipeline(fnm_lib, "moe_gather_matvec_multi")
  bf16_mp_pipe = metal_pipeline(fnm_lib, "bf16_matvec_multi_p")
  sdpa_pf_pipe = metal_pipeline(fnm_lib, "sdpa_prefill_multi_hd256")
  grouped_m_pipe = metal_pipeline(fnm_lib, "moe_grouped_matvec")
  moe_stage_pipe = metal_pipeline(fnm_lib, "moe_stage_x")
  moe_gemm_pipe = metal_pipeline(fnm_lib, "moe_gemm_m8")
  moe_stage_h_pipe = metal_pipeline(fnm_lib, "moe_stage_x_h")
  moe_gemm_h_pipe = metal_pipeline(fnm_lib, "moe_gemm_m8_h")
  # FN_MOEH=1 uses the half-MMA expert GEMM — measured SLOWER on M5
  # (2050 vs 1133 ms/chunk) AND ids diverge (half accumulation over
  # K=2560). Default stays f32 MMA; kept for re-testing on other silicon.
  moe_half = ccall("__w_env", "FN_MOEH") == "1"
  moe_sort_pipe = metal_pipeline(fnm_lib, "moe_sort_pairs")
  moe_out_m_pipe = metal_pipeline(fnm_lib, "moe_output_multi")
  ple_gate_m_pipe = metal_pipeline(fnm_lib, "ple_gate_multi")
  ple_conv_m_pipe = metal_pipeline(fnm_lib, "ple_conv_dilated_multi")
  conv_split_m_pipe = metal_pipeline(fnm_lib, "gdn_conv_split_multi")
  conv_par_pipe = metal_pipeline(fnm_lib, "gdn_conv_split_par")
  g_beta_m_pipe = metal_pipeline(fnm_lib, "gdn_g_beta_multi")
  phn_rope_m_pipe = metal_pipeline(fnm_lib, "fn_phn_rope_multi")
  dm_lib = metal_compile_source(device, read_file(QWEN_DIR + "decode_multi.metal"))
  embed_m_pipe = metal_pipeline(dm_lib, "bf16_embedding_lookup_multi")
  bf16_m_pipe = metal_pipeline(dm_lib, "bf16_matvec_multi")
  split_m_pipe = metal_pipeline(dm_lib, "split_q_gate_multi")
  slice_m_pipe = metal_pipeline(dm_lib, "copy_f32_slice_multi")
  kv_write_m_pipe = metal_pipeline(dm_lib, "kv_write_multi")
  sdpa_m_pipe = metal_pipeline(dm_lib, "sdpa_decode_multi_hd256")
  delta_m_pipe = metal_pipeline(dm_lib, "gated_delta_multi")
  fill_zero_pipe = metal_pipeline(metal_compile_source(device, read_file(FN_DIR + "fill_zero.metal")), "fill_zero")
  wide_grid_lib = metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_scaled_wide.metal"))
  bf16_gemm_lib = metal_compile_source(device, read_file(FN_DIR + "bf16_gemm_f32.metal"))
  bgemm_m16_pipe = metal_pipeline(bf16_gemm_lib, "bf16_gemm_f32_m16")
  bgemm_m32_pipe = metal_pipeline(bf16_gemm_lib, "bf16_gemm_f32_m32")
  bgemm_m64_pipe = metal_pipeline(bf16_gemm_lib, "bf16_gemm_f32_m64")
  bgemm_m128_pipe = metal_pipeline(bf16_gemm_lib, "bf16_gemm_f32_m128")
  nv_multi_pipes = []
  nv_multi_pipes_r2 = []
  bw = 1
  while bw <= 8
    nv_multi_pipes.push(metal_pipeline(wide_grid_lib, "nvfp4_wide_b" + bw.to_s + "_r1"))
    nv_multi_pipes_r2.push(metal_pipeline(wide_grid_lib, "nvfp4_wide_b" + bw.to_s + "_r2"))
    bw = bw + 1

  h_embed_m = metal_buffer(device, MULTI_MAX * HIDDEN * 4)
  h_m = metal_buffer(device, MULTI_MAX * HC_HIDDEN * 4)
  n_tmp_m = metal_buffer(device, MULTI_MAX * HC_HIDDEN * 4)
  lowrank_m = metal_buffer(device, MULTI_MAX * HC_LOWRANK * 4)
  upraw_m = metal_buffer(device, MULTI_MAX * HC_HIDDEN * 4)
  inj_m = metal_buffer(device, MULTI_MAX * HC_COUNT * 4)
  xn_m = metal_buffer(device, MULTI_MAX * HIDDEN * 4)
  y_m = metal_buffer(device, MULTI_MAX * HIDDEN * 4)
  qkv_m = metal_buffer(device, MULTI_MAX * QKV_DIM * 4)
  z_m = metal_buffer(device, MULTI_MAX * V_DIM * 4)
  a_m = metal_buffer(device, MULTI_MAX * HV * 4)
  b_m = metal_buffer(device, MULTI_MAX * HV * 4)
  mq_m = metal_buffer(device, MULTI_MAX * Q_DIM * 4)
  mk_m = metal_buffer(device, MULTI_MAX * K_DIM * 4)
  mv_m = metal_buffer(device, MULTI_MAX * V_DIM * 4)
  g_m = metal_buffer(device, MULTI_MAX * HV * 4)
  beta_m = metal_buffer(device, MULTI_MAX * HV * 4)
  delta_m_buf = metal_buffer(device, MULTI_MAX * V_DIM * 4)
  mnorm_m = metal_buffer(device, MULTI_MAX * V_DIM * 4)
  qfull_m = metal_buffer(device, MULTI_MAX * QFULL_DIM * 4)
  queries_m = metal_buffer(device, MULTI_MAX * ATTN_DIM * 4)
  agate_m = metal_buffer(device, MULTI_MAX * ATTN_DIM * 4)
  k_m = metal_buffer(device, MULTI_MAX * KV_DIM * 4)
  v_m = metal_buffer(device, MULTI_MAX * KV_DIM * 4)
  attn_m = metal_buffer(device, MULTI_MAX * ATTN_DIM * 4)
  cos_m = metal_buffer(device, MULTI_MAX * ROT_HALF * 4)
  sin_m = metal_buffer(device, MULTI_MAX * ROT_HALF * 4)
  rlog_m = metal_buffer(device, MULTI_MAX * N_EXPERTS * 4)
  tidx_m = metal_buffer(device, MULTI_MAX * TOP_K * 4)
  tw_m = metal_buffer(device, MULTI_MAX * TOP_K * 4)
  eg_m = metal_buffer(device, MULTI_MAX * TOP_K * MOE_FFN * 4)
  eu_m = metal_buffer(device, MULTI_MAX * TOP_K * MOE_FFN * 4)
  eh_m = metal_buffer(device, MULTI_MAX * TOP_K * MOE_FFN * 4)
  ed_m = metal_buffer(device, MULTI_MAX * TOP_K * HIDDEN * 4)
  sg_m = metal_buffer(device, MULTI_MAX * SHARED_FFN * 4)
  su_m = metal_buffer(device, MULTI_MAX * SHARED_FFN * 4)
  sh_m = metal_buffer(device, MULTI_MAX * SHARED_FFN * 4)
  shared_m = metal_buffer(device, MULTI_MAX * HIDDEN * 4)
  seg_m = metal_buffer(device, MULTI_MAX * 4)
  e_m = metal_buffer(device, MULTI_MAX * HIDDEN * 4)
  plk_m = metal_buffer(device, MULTI_MAX * HC_HIDDEN * 4)
  plkn_m = metal_buffer(device, MULTI_MAX * HC_HIDDEN * 4)
  plqn_m = metal_buffer(device, MULTI_MAX * HC_HIDDEN * 4)
  plv_m = metal_buffer(device, MULTI_MAX * HIDDEN * 4)
  plgv_m = metal_buffer(device, MULTI_MAX * HC_HIDDEN * 4)
  plnc_m = metal_buffer(device, MULTI_MAX * HC_HIDDEN * 4)
  # Per-layer stashes of the state-advancing inputs (conv input, normed k,
  # v, g, beta; PLE conv input) so a partial accept can tape-replay the
  # recurrent states for just the accepted prefix (~22 MB total).
  li = 0
  while li < N_LAYERS
    lyr = layers[li]
    if lyr[:kind] == "mamba"
      lyr[:qkv_v] = metal_buffer(device, 8 * QKV_DIM * 4)
      lyr[:mk_v] = metal_buffer(device, 8 * K_DIM * 4)
      lyr[:mv_v] = metal_buffer(device, 8 * V_DIM * 4)
      lyr[:g_v] = metal_buffer(device, 8 * HV * 4)
      lyr[:beta_v] = metal_buffer(device, 8 * HV * 4)
    if lyr[:ple] != nil
      lyr[:ple][:nc_v] = metal_buffer(device, 8 * HC_HIDDEN * 4)
    li = li + 1
  flip_defer = [0]
  logits_m = metal_buffer(device, PREFILL_LAST_MAX * N_VOCAB * 4)
  am_pv_m = metal_buffer(device, MULTI_MAX * ARGMAX_CHUNKS * 4)
  am_pi_m = metal_buffer(device, MULTI_MAX * ARGMAX_CHUNKS * 4)
  am_out_m = metal_buffer(device, MULTI_MAX * 4)
  tok_ids_m = metal_buffer(device, MULTI_MAX * 4)
  mpos_buf = metal_buffer(device, 4)
  order_m = metal_buffer(device, MULTI_MAX * TOP_K * 4)
  moe_offs_buf = metal_buffer(device, 513 * 4)
  xg_m = metal_buffer(device, (MULTI_MAX * TOP_K + 8) * HIDDEN * 4)
  if qsa_on
    idx_qk_m = metal_buffer(device, MULTI_MAX * IDX_DIM * 4)
    idx_q_m = metal_buffer(device, MULTI_MAX * 512 * 4)
    qsa_scores_m = metal_buffer(device, MULTI_MAX * QSA_MAXB * 4)
    qsa_sel_m = metal_buffer(device, MULTI_MAX * QSA_SEL_STRIDE * 4)
    qsa_ns_m = metal_buffer(device, MULTI_MAX * 4)
    qsa_nb_m = metal_buffer(device, MULTI_MAX * 4)
    qsa_vis_m = metal_buffer(device, MULTI_MAX * 4)

# Record-or-dispatch wrappers: with mrec set, the multi helpers append
# program steps instead of encoding, so a width's whole verify pass can be
# recorded once and replayed via w_metal_program_run (one bridge call).
mprog = []
mrec = [0]

-> mdg(pipe, args, g, tgs)
  if mrec[0] == 1
    mprog.push([0, pipe, args, g, tgs])
  else
    metal_dispatch_groups(queue, pipe, args, g, tgs)

-> mdn(pipe, args, nthreads)
  if mrec[0] == 1
    mprog.push([2, pipe, args, nthreads, 0])
  else
    metal_dispatch_n(queue, pipe, args, nthreads)

-> mbar(bufs)
  if mrec[0] == 1
    mprog.push([1, nil, bufs, 0, 0])

-> md3(pipe, args, dims)
  if mrec[0] == 1
    mprog.push([3, pipe, args, dims, 0])
  else
    metal_dispatch_3d(queue, pipe, args, dims[0], dims[1], dims[2], dims[3], dims[4], dims[5])

# Rung selection from autotune_qwen38fn.w wide: r1 collapses at n>=3 on
# big-row shapes (register pressure); r2 wins there; r1 stays best at
# rows<=640 (occupancy) and at width 1.
-> mv_multi(h, x_in, y_out, kdim, rows, n)
  if n > 8
    wraw = h.size() >= 3 ? h[3] : h[0]
    if rows <= 640 && n <= 64
      # latency, not bandwidth: small-row GEMM tiles leave the GPU idle
      # behind every barrier — rows x n/8 TGs instead
      mdg(bf16_mp_pipe, [wraw, x_in, y_out, kdim, rows, n], rows * ((n + 7) / 8), 32)
    elsif n > 32
      # tile the chunk into m64 slices (parallel dispatches, same barrier)
      m0 = 0
      while m0 < n
        mdg(bgemm_m64_pipe, [wraw, x_in, y_out, kdim, rows, n, m0], (rows + 31) / 32, 128)
        m0 = m0 + 64
    elsif n > 16
      mdg(bgemm_m32_pipe, [wraw, x_in, y_out, kdim, rows, n, 0], (rows + 31) / 32, 128)
    else
      mdg(bgemm_m16_pipe, [wraw, x_in, y_out, kdim, rows, n, 0], (rows + 31) / 32, 128)
  elsif h.size() >= 3
    if n >= 2 && rows > 640
      mdg(nv_multi_pipes_r2[n - 1], [h[0], h[1], x_in, y_out, kdim, rows, h[2]], (rows + 3) / 4, 64)
    else
      mdg(nv_multi_pipes[n - 1], [h[0], h[1], x_in, y_out, kdim, rows, h[2]], (rows + 1) / 2, 64)
  else
    mdg(bf16_m_pipe, [h[0], x_in, y_out, kdim, rows, n], rows, 32)

-> hc_mix_multi(hc, n)
  if skip_hc then return
  mdg(grms_m_pipe, [h_m, hc[:norm], n_tmp_m, HIDDEN, HC_COUNT, EPS], n * HC_COUNT, 256)
  if !skip_hcbar then mbar([n_tmp_m])
  if !skip_hcmv
    mv_multi(hc[:down], n_tmp_m, lowrank_m, HC_HIDDEN, HC_LOWRANK, n)
    mdg(bf16_mp_pipe, [hc[:inject], n_tmp_m, inj_m, HC_HIDDEN, HC_COUNT, n], HC_COUNT * ((n + 7) / 8), 32)
  if !skip_hcbar then mbar([lowrank_m])
  mdn(silu_div_pipe, [lowrank_m, lowrank_m, ~0.0 + HC_COUNT, n * HC_LOWRANK], n * HC_LOWRANK)
  if !skip_hcbar then mbar([lowrank_m])
  if !skip_hcmv
    mv_multi(hc[:up], lowrank_m, upraw_m, HC_LOWRANK, HC_HIDDEN, n)
  if !skip_hcbar then mbar([upraw_m])
  mdn(hc_mix_reduce_m_pipe, [upraw_m, n_tmp_m, xn_m, HC_COUNT, HIDDEN, n], n * HIDDEN)
  if !skip_hcbar then mbar([xn_m, inj_m])

-> hc_combine_multi_step(n)
  if skip_hc then return
  mdn(hc_combine_m_pipe, [h_m, y_m, inj_m, HC_COUNT, HIDDEN, n], n * HC_COUNT * HIDDEN)
  mbar([h_m])

-> mamba_multi(lyr, n)
  if skip_gdn then return
  ping = lyr[:ping]
  cs_in = ping == 0 ? lyr[:cs_a] : lyr[:cs_b]
  cs_out = ping == 0 ? lyr[:cs_b] : lyr[:cs_a]
  ss_in = ping == 0 ? lyr[:ss_a] : lyr[:ss_b]
  ss_out = ping == 0 ? lyr[:ss_b] : lyr[:ss_a]
  # verify widths (n<=8) stash conv/delta inputs per layer for the accept
  # walk's tape replay; prefill chunks use the shared wide scratch
  qkv_d = n <= 8 ? lyr[:qkv_v] : qkv_m
  mk_d = n <= 8 ? lyr[:mk_v] : mk_m
  mv_d = n <= 8 ? lyr[:mv_v] : mv_m
  g_d = n <= 8 ? lyr[:g_v] : g_m
  beta_d = n <= 8 ? lyr[:beta_v] : beta_m
  mv_multi(lyr[:qkv], xn_m, qkv_d, HIDDEN, QKV_DIM, n)
  mv_multi(lyr[:z], xn_m, z_m, HIDDEN, V_DIM, n)
  mdg(bf16_mp_pipe, [lyr[:a], xn_m, a_m, HIDDEN, HV, n], HV * ((n + 7) / 8), 32)
  mdg(bf16_mp_pipe, [lyr[:b], xn_m, b_m, HIDDEN, HV, n], HV * ((n + 7) / 8), 32)
  mbar([qkv_d])
  if n > 8
    mdn(conv_par_pipe, [lyr[:conv], cs_in, qkv_d, mq_m, mk_d, mv_d, cs_out, QKV_DIM, Q_DIM, K_DIM, n], n * QKV_DIM)
  else
    mdn(conv_split_m_pipe, [lyr[:conv], cs_in, qkv_d, mq_m, mk_d, mv_d, cs_out, QKV_DIM, Q_DIM, K_DIM, n], QKV_DIM)
  mbar([mq_m, mk_d, mv_d, a_m, b_m])
  mdg(phn_rope_m_pipe, [mq_m, q_norm_scale, cos_m, sin_m, DK, 0, HK, ~1.0 / DK, EPS / DK, n], n * HK, 32)
  mdg(phn_rope_m_pipe, [mk_d, k_norm_scale, cos_m, sin_m, DK, 0, HK, ~1.0 / DK, EPS / DK, n], n * HK, 32)
  mdn(g_beta_m_pipe, [a_m, b_m, lyr[:alog], lyr[:dtb], g_d, beta_d, HV, n], n * HV)
  mbar([mq_m, mk_d, g_d, beta_d])
  md3(delta_m_pipe, [mq_m, mk_d, mv_d, g_d, beta_d, ss_in, delta_m_buf, ss_out, HK, HV, DK, DV, n], [1, DV / 4, HV, 32, 4, 1])
  mbar([delta_m_buf, z_m])
  mdg(rng_sig_pipe, [delta_m_buf, z_m, lyr[:linear_norm], mnorm_m, DV, EPS], n * HV, 32)
  mbar([mnorm_m])
  mv_multi(lyr[:out], mnorm_m, y_m, V_DIM, HIDDEN, n)
  mbar([y_m])
  if flip_defer[0] == 0 then lyr[:ping] = 1 - ping

# pos_start for kv_write/sdpa is read from mpos_buf (contents rewritten per
# round) so recorded programs replay at any position.
-> full_multi(lyr, n)
  if skip_attn then return
  if qsa_on
    mv_multi(lyr[:idx_qk], xn_m, idx_qk_m, HIDDEN, IDX_DIM, n)
    mbar([idx_qk_m])
    mdn(slice_m_pipe, [idx_qk_m, idx_q_m, IDX_DIM, 512, 0, 512, n], n * 512)
    mdn(qsa_kw_pipe, [idx_qk_m, lyr[:idx_kc], mpos_buf, n], n * 128)
    mbar([idx_q_m, lyr[:idx_kc]])
    mdg(phn_rope_m_pipe, [idx_q_m, lyr[:idx_qn], cos_m, sin_m, 128, ROT_HALF, 4, ~1.0 / 128, EPS, n], n * 4, 32)
    mdg(qsa_build_pipe, [lyr[:idx_kc], lyr[:idx_kn], lyr[:idx_blk], qsa_range_buf, EPS, qsa_logb], MULTI_MAX / 4 + 1, 128)
    mbar([idx_q_m, lyr[:idx_blk]])
    mdg(qsa_scores_pipe, [idx_q_m, lyr[:idx_blk], qsa_scores_m, qsa_nb_m, QSA_MAXB, n], (n * QSA_MAXB + 255) / 256, 256)
    mbar([qsa_scores_m])
    mdg(qsa_select_pipe, [qsa_scores_m, qsa_nb_m, qsa_vis_m, qsa_sel_m, qsa_ns_m, QSA_MAXB, 512], n, 512)
    mbar([qsa_sel_m, qsa_ns_m])
  mv_multi(lyr[:q], xn_m, qfull_m, HIDDEN, QFULL_DIM, n)
  mv_multi(lyr[:k], xn_m, k_m, HIDDEN, KV_DIM, n)
  mv_multi(lyr[:v], xn_m, v_m, HIDDEN, KV_DIM, n)
  mbar([qfull_m])
  mdn(split_m_pipe, [qfull_m, queries_m, agate_m, N_HEADS, HEAD_DIM, n], n * ATTN_DIM)
  mbar([queries_m, k_m])
  mdg(phn_rope_m_pipe, [queries_m, lyr[:qn], cos_m, sin_m, HEAD_DIM, ROT_HALF, N_HEADS, ~1.0 / HEAD_DIM, EPS, n], n * N_HEADS, 32)
  mdg(phn_rope_m_pipe, [k_m, lyr[:kn], cos_m, sin_m, HEAD_DIM, ROT_HALF, N_KV_HEADS, ~1.0 / HEAD_DIM, EPS, n], n * N_KV_HEADS, 32)
  mbar([queries_m, k_m, v_m])
  mdn(kv_write_m_pipe, [k_m, v_m, lyr[:k_cache], lyr[:v_cache], mpos_buf, KV_DIM, n], n * KV_DIM)
  mbar([lyr[:k_cache], lyr[:v_cache]])
  if qsa_on
    mdg(qsa_sdpa_pipe, [queries_m, lyr[:k_cache], lyr[:v_cache], attn_m, qsa_sel_m, qsa_ns_m, GQA, N_HEADS, KV_DIM, ATTN_SCALE, QSA_SEL_STRIDE, n], n * N_HEADS, 256)
  elsif n > 8
    # thread-per-position scores: no per-position barriers (prefill shape).
    # NOT bit-identical to the decode sdpa (different dot order) — the
    # chunked prefill is ids-gated, and verify widths (n<=8) keep the
    # bit-exact kernel.
    mdg(sdpa_pf_pipe, [queries_m, lyr[:k_cache], lyr[:v_cache], attn_m, GQA, mpos_buf, N_HEADS, KV_DIM, ATTN_SCALE, n], n * N_HEADS, 256)
  else
    mdg(sdpa_m_pipe, [queries_m, lyr[:k_cache], lyr[:v_cache], attn_m, GQA, mpos_buf, N_HEADS, KV_DIM, ATTN_SCALE, n], n * N_HEADS, 256)
  mbar([attn_m, agate_m])
  mdn(gate_pipe, [attn_m, agate_m, n * ATTN_DIM], n * ATTN_DIM)
  mbar([attn_m])
  mv_multi(lyr[:out], attn_m, y_m, ATTN_DIM, HIDDEN, n)
  mbar([y_m])

-> moe_multi(lyr, n)
  if skip_moe then return
  ex = lyr[:experts]
  og = ex[:offs]["gate_proj"]
  ou = ex[:offs]["up_proj"]
  od = ex[:offs]["down_proj"]
  q = ex[:quarters]
  mv_multi(lyr[:router], xn_m, rlog_m, HIDDEN, N_EXPERTS, n)
  if !skip_moeshared
    mv_multi(lyr[:sh_gate], xn_m, sg_m, HIDDEN, SHARED_FFN, n)
    mv_multi(lyr[:sh_up], xn_m, su_m, HIDDEN, SHARED_FFN, n)
  mdg(bf16_mp_pipe, [lyr[:sh_seg], xn_m, seg_m, HIDDEN, 1, n], (n + 7) / 8, 32)
  mbar([rlog_m, sg_m, su_m])
  mdg(router_m_pipe, [rlog_m, tidx_m, tw_m], n, 512)
  mdn(silu_pipe, [sg_m, su_m, sh_m, n * SHARED_FFN], n * SHARED_FFN)
  mbar([tidx_m, sh_m])
  mdg(moe_sort_pipe, [tidx_m, order_m, n * TOP_K, moe_offs_buf], 1, 512)
  mbar([order_m, moe_offs_buf])
  if n > 8
    # prefill: stage activations expert-contiguous, then per-expert MMA GEMM
    # (one nibble decode per weight per 8-token m-tile, matrix-unit math)
    sp = moe_half ? moe_stage_h_pipe : moe_stage_pipe
    gp = moe_half ? moe_gemm_h_pipe : moe_gemm_pipe
    if !skip_moestage
      mdn(sp, [xn_m, xg_m, order_m, HIDDEN, TOP_K, 0, n * TOP_K], n * TOP_K * HIDDEN)
      mbar([xg_m])
    if !skip_moegemm
      mdg(gp, [q[0], q[1], q[2], q[3], order_m, moe_offs_buf, ex[:slot_map], xg_m, eg_m, HIDDEN, MOE_FFN, og[0], og[1], og[2], og[3], og[4], og[5]], 512 * (MOE_FFN / 32), 128)
      mdg(gp, [q[0], q[1], q[2], q[3], order_m, moe_offs_buf, ex[:slot_map], xg_m, eu_m, HIDDEN, MOE_FFN, ou[0], ou[1], ou[2], ou[3], ou[4], ou[5]], 512 * (MOE_FFN / 32), 128)
  else
    mdg(gather_m_pipe, [q[0], q[1], q[2], q[3], tidx_m, ex[:slot_map], xn_m, eg_m, HIDDEN, MOE_FFN, og[0], og[1], og[2], og[3], og[4], og[5], TOP_K, 0, ex[:hot], og[6], og[7], og[8], order_m], n * TOP_K * (MOE_FFN / 8), 64)
    mdg(gather_m_pipe, [q[0], q[1], q[2], q[3], tidx_m, ex[:slot_map], xn_m, eu_m, HIDDEN, MOE_FFN, ou[0], ou[1], ou[2], ou[3], ou[4], ou[5], TOP_K, 0, ex[:hot], ou[6], ou[7], ou[8], order_m], n * TOP_K * (MOE_FFN / 8), 64)
  mv_multi(lyr[:sh_down], sh_m, shared_m, SHARED_FFN, HIDDEN, n)
  mbar([eg_m, eu_m])
  mdn(silu_pipe, [eg_m, eu_m, eh_m, n * TOP_K * MOE_FFN], n * TOP_K * MOE_FFN)
  mbar([eh_m])
  if n > 8
    sp2 = moe_half ? moe_stage_h_pipe : moe_stage_pipe
    gp2 = moe_half ? moe_gemm_h_pipe : moe_gemm_pipe
    if !skip_moestage
      mdn(sp2, [eh_m, xg_m, order_m, MOE_FFN, TOP_K, 1, n * TOP_K], n * TOP_K * MOE_FFN)
      mbar([xg_m])
    if !skip_moegemm
      mdg(gp2, [q[0], q[1], q[2], q[3], order_m, moe_offs_buf, ex[:slot_map], xg_m, ed_m, MOE_FFN, HIDDEN, od[0], od[1], od[2], od[3], od[4], od[5]], 512 * (HIDDEN / 32), 128)
  else
    mdg(gather_m_pipe, [q[0], q[1], q[2], q[3], tidx_m, ex[:slot_map], eh_m, ed_m, MOE_FFN, HIDDEN, od[0], od[1], od[2], od[3], od[4], od[5], TOP_K, 1, ex[:hot], od[6], od[7], od[8], order_m], n * TOP_K * (HIDDEN / 8), 64)
  mbar([ed_m, tw_m, shared_m, seg_m])
  mdn(moe_out_m_pipe, [ed_m, tw_m, shared_m, seg_m, y_m, TOP_K, HIDDEN, n], n * HIDDEN)
  mbar([y_m])

-> ple_multi(lyr, n)
  if skip_ple then return
  pp = lyr[:ple]
  ping = pp[:ping]
  cs_in = ping == 0 ? pp[:cs_a] : pp[:cs_b]
  cs_out = ping == 0 ? pp[:cs_b] : pp[:cs_a]
  mv_multi(pp[:key], e_m, plk_m, HIDDEN, HC_HIDDEN, n)
  mv_multi(pp[:value], e_m, plv_m, HIDDEN, HIDDEN, n)
  mdg(grms_m_pipe, [h_m, pp[:norm_query], plqn_m, HIDDEN, HC_COUNT, EPS], n * HC_COUNT, 256)
  mbar([plk_m, plqn_m])
  mdg(grms_m_pipe, [plk_m, pp[:norm_key], plkn_m, HIDDEN, HC_COUNT, EPS], n * HC_COUNT, 256)
  mbar([plkn_m, plv_m])
  mdg(ple_gate_m_pipe, [plkn_m, plqn_m, plv_m, plgv_m, HIDDEN, HC_COUNT], n * HC_COUNT, 256)
  mbar([plgv_m])
  nc_d = n <= 8 ? pp[:nc_v] : plnc_m
  mdg(grms_m_pipe, [plgv_m, pp[:norm_conv], nc_d, HIDDEN, HC_COUNT, EPS], n * HC_COUNT, 256)
  mbar([nc_d])
  mdn(ple_conv_m_pipe, [pp[:conv], cs_in, nc_d, plgv_m, h_m, cs_out, HC_HIDDEN, n], n * HC_HIDDEN)
  mbar([h_m])
  if flip_defer[0] == 0 then pp[:ping] = 1 - ping

-> head_multi(n)
  mdg(grms_m_pipe, [h_m, mixer[:norm], n_tmp_m, HIDDEN, HC_COUNT, EPS], n * HC_COUNT, 256)
  mbar([n_tmp_m])
  mv_multi(mixer[:down], n_tmp_m, lowrank_m, HC_HIDDEN, HC_LOWRANK, n)
  mbar([lowrank_m])
  mdn(silu_div_pipe, [lowrank_m, lowrank_m, ~0.0 + HC_COUNT, n * HC_LOWRANK], n * HC_LOWRANK)
  mbar([lowrank_m])
  mv_multi(mixer[:up], lowrank_m, upraw_m, HC_LOWRANK, HC_HIDDEN, n)
  mbar([upraw_m])
  mdn(hc_mix_reduce_m_pipe, [upraw_m, n_tmp_m, xn_m, HC_COUNT, HIDDEN, n], n * HIDDEN)
  mbar([xn_m])
  mv_multi(lm_head, xn_m, logits_m, HIDDEN, N_VOCAB, n)
  mbar([logits_m])
  mdg(argmax_stage1_pipe, [logits_m, am_pv_m, am_pi_m, N_VOCAB, ARGMAX_CHUNKS, n], n * ARGMAX_CHUNKS, 256)
  mbar([am_pv_m, am_pi_m])
  mdg(argmax_stage2_pipe, [am_pv_m, am_pi_m, am_out_m, ARGMAX_CHUNKS, n], n, 256)

# Emit the whole width-n pass through the wrappers (record or dispatch).
-> multi_body(n)
  mdn(embed_m_pipe, [embed_w, h_embed_m, tok_ids_m, HIDDEN, n], n * HIDDEN)
  mbar([h_embed_m])
  t = 0
  while t < n
    s = 0
    while s < HC_COUNT
      mdn(copy_at_pipe, [h_embed_m, h_m, t * HIDDEN, t * HC_HIDDEN + s * HIDDEN, HIDDEN], HIDDEN)
      s = s + 1
    t = t + 1
  mbar([h_m])
  li = 0
  while li < N_LAYERS
    lyr = layers[li]
    if lyr[:ple] != nil then ple_multi(lyr, n)
    hc_mix_multi(lyr[:attn_hc], n)
    if lyr[:kind] == "mamba"
      mamba_multi(lyr, n)
    else
      full_multi(lyr, n)
    hc_combine_multi_step(n)
    hc_mix_multi(lyr[:mlp_hc], n)
    moe_multi(lyr, n)
    hc_combine_multi_step(n)
    li = li + 1
  if multi_head_on[0] == 1 then head_multi(n)

# Recorded programs per (width, mamba ping parity): the ping choice is baked
# into the recorded args, and every mamba/PLE layer flips exactly once per
# verify round, so parity is global.
multi_progs = {}
# 0 during interior prefill chunks: skip the mixer + lm_head + argmax (only
# the last chunk needs logits) — saves ~360 MB of lm_head stream per chunk.
multi_head_on = [1]

-> record_multi_prog(n)
  while mprog.size() > 0
    mprog.pop()
  mrec[0] = 1
  fd = flip_defer[0]
  flip_defer[0] = 1
  multi_body(n)
  flip_defer[0] = fd
  mrec[0] = 0
  out = []
  i2 = 0
  while i2 < mprog.size()
    out.push(mprog[i2])
    i2 = i2 + 1
  out

-> forward_multi(toks, pos0, n)
  t = 0
  while t < n
    ple_gather([toks[t], e_m, t * HIDDEN])
    ple_advance(toks[t])
    metal_buffer_write_i32(tok_ids_m, t, toks[t])
    ri = 0
    while ri < ROT_HALF
      theta = Math.exp(log_rope * (~0.0 - ri * rope_power))
      angle = (pos0 + t) * theta
      metal_buffer_write_f32(cos_m, t * ROT_HALF + ri, Math.cos(angle))
      metal_buffer_write_f32(sin_m, t * ROT_HALF + ri, Math.sin(angle))
      ri = ri + 1
    t = t + 1
  metal_buffer_write_i32(mpos_buf, 0, pos0)
  if qsa_on
    t = 0
    while t < n
      metal_buffer_write_i32(qsa_nb_m, t, (pos0 + t + 1) / 4)
      metal_buffer_write_i32(qsa_vis_m, t, pos0 + t + 1)
      t = t + 1
    metal_buffer_write_i32(qsa_range_buf, 0, pos0 / 4)
    metal_buffer_write_i32(qsa_range_buf, 1, (pos0 + n) / 4)
  prog_key = (n * 2 + layers[0][:ping]) * 2 + multi_head_on[0]
  if multi_progs[prog_key] == nil
    multi_progs[prog_key] = record_multi_prog(n)
  metal_batch_begin_concurrent(queue)
  # ccall int LITERALS miscompile (see memory) — pass the flag via a variable
  with_barriers = 2 - 1
  ccall("w_metal_program_run", queue, multi_progs[prog_key], with_barriers)
  metal_batch_commit(queue)
  # replayed programs can't flip pings as a side effect — do it here unless
  # the caller (spec loop) defers flips to its rollback
  if flip_defer[0] == 0
    li = 0
    while li < N_LAYERS
      lyr = layers[li]
      if lyr[:kind] == "mamba" then lyr[:ping] = 1 - lyr[:ping]
      if lyr[:ple] != nil then lyr[:ple][:ping] = 1 - lyr[:ple][:ping]
      li = li + 1
  preds = []
  t = 0
  while t < n
    preds.push(metal_buffer_read_i32(am_out_m, t))
    t = t + 1
  preds

-> zero_buf(buf, n_floats)
  metal_dispatch_n(queue, fill_zero_pipe, [buf, n_floats], n_floats)

-> reset_states
  metal_batch_begin(queue)
  li = 0
  while li < N_LAYERS
    lyr = layers[li]
    if lyr[:kind] == "mamba"
      zero_buf(lyr[:cs_a], 3 * QKV_DIM)
      zero_buf(lyr[:cs_b], 3 * QKV_DIM)
      zero_buf(lyr[:ss_a], HV * DV * DK)
      zero_buf(lyr[:ss_b], HV * DV * DK)
      lyr[:ping] = 0
    if lyr[:ple] != nil
      zero_buf(lyr[:ple][:cs_a], 9 * HC_HIDDEN)
      zero_buf(lyr[:ple][:cs_b], 9 * HC_HIDDEN)
      lyr[:ple][:ping] = 0
    li = li + 1
  metal_batch_commit(queue)
  ple_ctx[0] = EOS_TOKEN
  ple_ctx[1] = EOS_TOKEN

# ---- MTP head (FN_MTP=1: draft-acceptance harness) ------------------------
# Semantics per vLLM qwen4_exp mtp.py: the head consumes the PRE-mixer 10240
# hyper-connection stream h_p plus emb(t_{p+1}); RMS-norm each (the hidden
# norm runs over the FULL flattened 10240), project through fc_hidden (per
# branch) / fc_embedding, broadcast-add the embedding into all 4 branches,
# run ONE full-attention+MoE layer (own HCs; kv slot = position-1 since MTP
# position 0 never exists; rope at the REAL position), collapse through its
# own mixer, share lm_head. The MTP MoE is bf16 with FUSED gate|up experts.
if mtp_depth > 0
  mtp_ops_lib = metal_compile_source(device, read_file(FN_DIR + "mtp_ops.metal"))
  mtp_fuse_pipe = metal_pipeline(mtp_ops_lib, "mtp_fuse_add")
  mtp_gather_pipe = metal_pipeline(mtp_ops_lib, "bf16_moe_gather_multi")
  mtp_gu_silu_pipe = metal_pipeline(mtp_ops_lib, "mtp_gu_silu")
  mtp_pre_norm_e = metal_buffer(device, HIDDEN * 4)
  mtp_pre_norm_h = metal_buffer(device, HC_HIDDEN * 4)
  load_shifted_norm(["mtp.pre_fc_norm_embedding.weight", HIDDEN, mtp_pre_norm_e])
  load_shifted_norm(["mtp.pre_fc_norm_hidden.weight", HC_HIDDEN, mtp_pre_norm_h])
  mtp_qn = metal_buffer(device, HEAD_DIM * 4)
  mtp_kn = metal_buffer(device, HEAD_DIM * 4)
  load_shifted_norm(["mtp.layers.0.self_attn.q_norm.weight", HEAD_DIM, mtp_qn])
  load_shifted_norm(["mtp.layers.0.self_attn.k_norm.weight", HEAD_DIM, mtp_kn])
  mtp_lyr = {
    kind: "full",
    q: mv_tensor("mtp.layers.0.self_attn.q_proj.weight"),
    k: mv_tensor("mtp.layers.0.self_attn.k_proj.weight"),
    v: mv_tensor("mtp.layers.0.self_attn.v_proj.weight"),
    out: mv_tensor("mtp.layers.0.self_attn.o_proj.weight"),
    qn: mtp_qn,
    kn: mtp_kn,
    k_cache: metal_buffer(device, MAX_POS * KV_DIM * 4),
    v_cache: metal_buffer(device, MAX_POS * KV_DIM * 4)
  }
  mtp_attn_hc = load_hc("mtp.layers.0.attn_hyper_connection.")
  mtp_mlp_hc = load_hc("mtp.layers.0.mlp_hyper_connection.")
  mtp_mixer = load_hc("mtp.hyper_connection_mixer.")
  mtp_router = mv_tensor("mtp.layers.0.mlp.gate.weight")
  mtp_sh_gate = mv_tensor("mtp.layers.0.mlp.shared_expert.gate_proj.weight")
  mtp_sh_up = mv_tensor("mtp.layers.0.mlp.shared_expert.up_proj.weight")
  mtp_sh_down = mv_tensor("mtp.layers.0.mlp.shared_expert.down_proj.weight")
  mtp_seg = raw_tensor("mtp.layers.0.mlp.shared_expert_gate.weight")
  mtp_experts_gu = raw_tensor("mtp.layers.0.mlp.experts.gate_up_proj")
  mtp_experts_dn = raw_tensor("mtp.layers.0.mlp.experts.down_proj")
  mtp_fc_e = raw_tensor("mtp.fc_embedding.weight")
  mtp_fc_h = raw_tensor("mtp.fc_hidden.weight")
  mtp_en_m = metal_buffer(device, MULTI_MAX * HIDDEN * 4)
  mtp_ef_m = metal_buffer(device, MULTI_MAX * HIDDEN * 4)
  mtp_hn_m = metal_buffer(device, MULTI_MAX * HC_HIDDEN * 4)
  mtp_hf_m = metal_buffer(device, MULTI_MAX * HC_HIDDEN * 4)
  egu_m = metal_buffer(device, MULTI_MAX * TOP_K * 2 * MOE_FFN * 4)

-> mtp_moe_multi(n)
  mv_multi(mtp_router, xn_m, rlog_m, HIDDEN, N_EXPERTS, n)
  mv_multi(mtp_sh_gate, xn_m, sg_m, HIDDEN, SHARED_FFN, n)
  mv_multi(mtp_sh_up, xn_m, su_m, HIDDEN, SHARED_FFN, n)
  mdg(bf16_m_pipe, [mtp_seg, xn_m, seg_m, HIDDEN, 1, n], 1, 32)
  mbar([rlog_m, sg_m, su_m])
  mdg(router_m_pipe, [rlog_m, tidx_m, tw_m], n, 512)
  mdn(silu_pipe, [sg_m, su_m, sh_m, n * SHARED_FFN], n * SHARED_FFN)
  mbar([tidx_m, sh_m])
  mdg(mtp_gather_pipe, [mtp_experts_gu, tidx_m, xn_m, egu_m, HIDDEN, 2 * MOE_FFN, 2 * MOE_FFN * HIDDEN, 0, TOP_K, 0], n * TOP_K * (2 * MOE_FFN / 8), 64)
  mv_multi(mtp_sh_down, sh_m, shared_m, SHARED_FFN, HIDDEN, n)
  mbar([egu_m])
  mdn(mtp_gu_silu_pipe, [egu_m, eh_m, MOE_FFN, n * TOP_K * MOE_FFN], n * TOP_K * MOE_FFN)
  mbar([eh_m])
  mdg(mtp_gather_pipe, [mtp_experts_dn, tidx_m, eh_m, ed_m, MOE_FFN, HIDDEN, HIDDEN * MOE_FFN, 0, TOP_K, 1], n * TOP_K * (HIDDEN / 8), 64)
  mbar([ed_m, tw_m, shared_m, seg_m])
  mdn(moe_out_m_pipe, [ed_m, tw_m, shared_m, seg_m, y_m, TOP_K, HIDDEN, n], n * HIDDEN)
  mbar([y_m])

-> mtp_fuse_gpu(hsrc, n)
  mdn(embed_m_pipe, [embed_w, e_m, tok_ids_m, HIDDEN, n], n * HIDDEN)
  mdg(grms_m_pipe, [hsrc, mtp_pre_norm_h, mtp_hn_m, HC_HIDDEN, 1, EPS], n, 256)
  mbar([e_m, mtp_hn_m])
  mdg(grms_m_pipe, [e_m, mtp_pre_norm_e, mtp_en_m, HIDDEN, 1, EPS], n, 256)
  mdg(bf16_m_pipe, [mtp_fc_h, mtp_hn_m, mtp_hf_m, HIDDEN, HIDDEN, n * HC_COUNT], HIDDEN, 32)
  mbar([mtp_en_m])
  mdg(bf16_m_pipe, [mtp_fc_e, mtp_en_m, mtp_ef_m, HIDDEN, HIDDEN, n], HIDDEN, 32)
  mbar([mtp_ef_m, mtp_hf_m])
  mdn(mtp_fuse_pipe, [mtp_hf_m, mtp_ef_m, h_m, HC_COUNT, HIDDEN, n], n * HC_HIDDEN)
  mbar([h_m])

-> mtp_rope(pos0, n)
  t = 0
  while t < n
    ri = 0
    while ri < ROT_HALF
      theta = Math.exp(log_rope * (~0.0 - ri * rope_power))
      angle = (pos0 + t) * theta
      metal_buffer_write_f32(cos_m, t * ROT_HALF + ri, Math.cos(angle))
      metal_buffer_write_f32(sin_m, t * ROT_HALF + ri, Math.sin(angle))
      ri = ri + 1
    t = t + 1

-> mtp_head_multi(n)
  mdg(grms_m_pipe, [h_m, mtp_mixer[:norm], n_tmp_m, HIDDEN, HC_COUNT, EPS], n * HC_COUNT, 256)
  mbar([n_tmp_m])
  mv_multi(mtp_mixer[:down], n_tmp_m, lowrank_m, HC_HIDDEN, HC_LOWRANK, n)
  mbar([lowrank_m])
  mdn(silu_div_pipe, [lowrank_m, lowrank_m, ~0.0 + HC_COUNT, n * HC_LOWRANK], n * HC_LOWRANK)
  mbar([lowrank_m])
  mv_multi(mtp_mixer[:up], lowrank_m, upraw_m, HC_LOWRANK, HC_HIDDEN, n)
  mbar([upraw_m])
  mdn(hc_mix_reduce_m_pipe, [upraw_m, n_tmp_m, xn_m, HC_COUNT, HIDDEN, n], n * HIDDEN)
  mbar([xn_m])
  mv_multi(lm_head, xn_m, logits_m, HIDDEN, N_VOCAB, n)
  mbar([logits_m])
  mdg(argmax_stage1_pipe, [logits_m, am_pv_m, am_pi_m, N_VOCAB, ARGMAX_CHUNKS, n], n * ARGMAX_CHUNKS, 256)
  mbar([am_pv_m, am_pi_m])
  mdg(argmax_stage2_pipe, [am_pv_m, am_pi_m, am_out_m, ARGMAX_CHUNKS, n], n, 256)

# One MTP draft: fuse (H, emb(next_tok)) at real position pos_real (kv slot
# pos_real-1), run the head layer, return the drafted token id.
-> mtp_body(hsrc, n)
  mtp_fuse_gpu(hsrc, n)
  hc_mix_multi(mtp_attn_hc, n)
  full_multi(mtp_lyr, n)
  hc_combine_multi_step(n)
  hc_mix_multi(mtp_mlp_hc, n)
  mtp_moe_multi(n)
  hc_combine_multi_step(n)
  if multi_head_on[0] == 1 then mtp_head_multi(n)

# Recorded draft programs: variant 0 fuses from the main H, variant 1 from
# the MTP layer's own h_m (chained drafts). Everything token-dependent flows
# through tok_ids_m / cos_m / mpos_buf.
mtp_progs = [nil, nil]

-> mtp_step(next_tok, pos_real, variant)
  mtp_rope(pos_real, 1)
  metal_buffer_write_i32(mpos_buf, 0, pos_real - 1)
  metal_buffer_write_i32(tok_ids_m, 0, next_tok)
  hsrc = variant == 0 ? H : h_m
  if mtp_progs[variant] == nil
    while mprog.size() > 0
      mprog.pop()
    mrec[0] = 1
    mtp_body(hsrc, 1)
    mrec[0] = 0
    rec_out = []
    ri2 = 0
    while ri2 < mprog.size()
      rec_out.push(mprog[ri2])
      ri2 = ri2 + 1
    mtp_progs[variant] = rec_out
  metal_batch_begin_concurrent(queue)
  with_barriers2 = 2 - 1
  ccall("w_metal_program_run", queue, mtp_progs[variant], with_barriers2)
  metal_batch_commit(queue)
  metal_buffer_read_i32(am_out_m, 0)

# Width-n MTP prefill: populate the MTP kv cache for a whole chunk in one
# recorded pass (fuses h_m[t] with emb(next_toks[t]); head skipped — only kv
# writes matter during prefill).
mtp_pf_progs = {}

-> mtp_prefill_chunk(next_toks, pos0, n)
  t = 0
  while t < n
    metal_buffer_write_i32(tok_ids_m, t, next_toks[t])
    t = t + 1
  mtp_rope(pos0, n)
  metal_buffer_write_i32(mpos_buf, 0, pos0 - 1)
  pf_key = n
  if mtp_pf_progs[pf_key] == nil
    while mprog.size() > 0
      mprog.pop()
    mrec[0] = 1
    hd_save = multi_head_on[0]
    multi_head_on[0] = 0
    mtp_body(h_m, n)
    multi_head_on[0] = hd_save
    mrec[0] = 0
    rec2 = []
    ci = 0
    while ci < mprog.size()
      rec2.push(mprog[ci])
      ci = ci + 1
    mtp_pf_progs[pf_key] = rec2
  metal_batch_begin_concurrent(queue)
  wb2 = 2 - 1
  ccall("w_metal_program_run", queue, mtp_pf_progs[pf_key], wb2)
  metal_batch_commit(queue)

# Recompute the recurrent states for the accepted prefix (tape replay from
# the per-layer stashes) and flip all deferred pings. On a full accept the
# verify's own final states are already right — only the flips remain.
# Also refreshes H (width-1 stream) from the last accepted verify position.
-> spec_rollback(spec)
  n_keep = spec[0]
  full = spec[1]
  metal_batch_begin(queue)
  li = 0
  while li < N_LAYERS
    lyr = layers[li]
    if lyr[:ple] != nil
      pp = lyr[:ple]
      pping = pp[:ping]
      if n_keep < full
        metal_dispatch_n(queue, ple_conv_m_pipe, [pp[:conv], pping == 0 ? pp[:cs_a] : pp[:cs_b], pp[:nc_v], plgv_m, plk_m, pping == 0 ? pp[:cs_b] : pp[:cs_a], HC_HIDDEN, n_keep], n_keep * HC_HIDDEN)
      pp[:ping] = 1 - pping
    if lyr[:kind] == "mamba"
      ping = lyr[:ping]
      if n_keep < full
        cs_in = ping == 0 ? lyr[:cs_a] : lyr[:cs_b]
        cs_out = ping == 0 ? lyr[:cs_b] : lyr[:cs_a]
        ss_in = ping == 0 ? lyr[:ss_a] : lyr[:ss_b]
        ss_out = ping == 0 ? lyr[:ss_b] : lyr[:ss_a]
        metal_dispatch_n(queue, conv_split_m_pipe, [lyr[:conv], cs_in, lyr[:qkv_v], mq_m, mk_m, mv_m, cs_out, QKV_DIM, Q_DIM, K_DIM, n_keep], QKV_DIM)
        metal_dispatch_3d(queue, delta_m_pipe, [lyr[:mk_v], lyr[:mk_v], lyr[:mv_v], lyr[:g_v], lyr[:beta_v], ss_in, delta_m_buf, ss_out, HK, HV, DK, DV, n_keep], 1, DV / 4, HV, 32, 4, 1)
      lyr[:ping] = 1 - ping
    li = li + 1
  metal_dispatch_n(queue, copy_at_pipe, [h_m, H, (n_keep - 1) * HC_HIDDEN, 0, HC_HIDDEN], HC_HIDDEN)
  metal_batch_commit(queue)

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
# Chunked prefill: PREFILL_CHUNK-token blocks through the recorded multi
# path (quant projections on nvfp4_gemm_f32 m-tiles). Interior chunks skip
# the head. FN_CHUNK=0 forces the serial token-by-token prefill (A/B and
# ids gate). GEMM MMA summation is NOT bit-identical to the matvec family —
# gate chunked-vs-serial on ids, like the 27B did.
prefill_chunked = prompt.size() > 8 && ccall("__w_env", "FN_CHUNK") != "0"
if prefill_chunked
  while i < prompt.size()
    remaining = prompt.size() - i
    cw = remaining
    if cw > PREFILL_CHUNK then cw = PREFILL_CHUNK
    # the head-bearing final chunk must fit logits_m: shave this chunk so the
    # tail lands in (0, PREFILL_LAST_MAX]
    if remaining > cw && remaining - cw > 0 && remaining - cw < 1
      cw = cw
    if cw == remaining && cw > PREFILL_LAST_MAX
      cw = remaining - PREFILL_LAST_MAX
    chunk = prompt.slice(i, cw)
    is_last = i + cw >= prompt.size()
    multi_head_on[0] = is_last ? 1 : 0
    ct0 = ccall("__w_clock_ms")
    pf_preds = forward_multi(chunk, i, cw)
    if fn_time then << "  chunk @" + i.to_s + " w" + cw.to_s + ": " + (ccall("__w_clock_ms") - ct0).to_s + " ms"
    if is_last then pred = pf_preds[cw - 1]
    if mtp_depth > 0
      nxt = []
      ti = 0
      while ti < cw
        nxt.push(i + ti + 1 < prompt.size() ? prompt[i + ti + 1] : pred)
        ti = ti + 1
      mtp_prefill_chunk(nxt, i + 1, cw)
    if is_last
      # the spec loop and FN_MTP harness fuse drafts from H (width-1 stream);
      # forward_multi only fills h_m — publish the final position's stream
      metal_batch_begin(queue)
      metal_dispatch_n(queue, copy_at_pipe, [h_m, H, (cw - 1) * HC_HIDDEN, 0, HC_HIDDEN], HC_HIDDEN)
      metal_batch_commit(queue)
    i = i + cw
  multi_head_on[0] = 1
else
  while i < prompt.size()
    pred = forward(prompt[i], i, i == prompt.size() - 1)
    if mtp_depth > 0
      mtp_step(i + 1 < prompt.size() ? prompt[i + 1] : pred, i + 1, 0)
    i = i + 1
if mtp_depth > 0 && ccall("__w_env", "FN_DUMP_MTPKV") != nil && ccall("__w_env", "FN_DUMP_MTPKV") != ""
  File.write_bytes(ccall("__w_env", "FN_DUMP_MTPKV") + ".k", metal_buffer_view(mtp_lyr[:k_cache], 8, MAX_POS * KV_DIM * 4))
  File.write_bytes(ccall("__w_env", "FN_DUMP_MTPKV") + ".v", metal_buffer_view(mtp_lyr[:v_cache], 8, MAX_POS * KV_DIM * 4))
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
spec_rounds = 0
accept_hist = [0, 0, 0, 0, 0, 0, 0, 0]
if mtp_spec > 0
  cur = pred
  while ids.size() < n_generate
    rt0 = ccall("__w_clock_ms")
    d = mtp_adaptive == 1 ? mtp_d_cur[0] : mtp_spec
    if pos + d + 1 > MAX_POS then d = MAX_POS - pos - 1
    if d < 0 then d = 0
    st0 = fn_time ? ccall("__w_clock_ms") : ~0.0
    drafts = []
    di = 0
    while di < d
      drafts.push(mtp_step(di == 0 ? cur : drafts[di - 1], pos + 1 + di, di == 0 ? 0 : 1))
      di = di + 1
    st1 = fn_time ? ccall("__w_clock_ms") : ~0.0
    block = [cur]
    di = 0
    while di < d
      block.push(drafts[di])
      di = di + 1
    sctx0 = ple_ctx[0]
    sctx1 = ple_ctx[1]
    flip_defer[0] = 1
    preds = forward_multi(block, pos, d + 1)
    flip_defer[0] = 0
    st2 = fn_time ? ccall("__w_clock_ms") : ~0.0
    a = 0
    while a < d && drafts[a] == preds[a]
      a = a + 1
    ei = 0
    while ei <= a
      ids.push(preds[ei])
      ei = ei + 1
    n_keep = a + 1
    if n_keep < d + 1
      ple_ctx[0] = sctx0
      ple_ctx[1] = sctx1
      ki = 0
      while ki < n_keep
        ple_advance(block[ki])
        ki = ki + 1
    spec_rollback([n_keep, d + 1])
    if fn_time
      encode_ms[0] = encode_ms[0] + (st1 - st0)
      encode_ms[1] = encode_ms[1] + (st2 - st1)
      encode_ms[2] = encode_ms[2] + (ccall("__w_clock_ms") - st2)
      encode_ms[3] = encode_ms[3] + 1
    spec_rounds = spec_rounds + 1
    accept_hist[a] = accept_hist[a] + 1
    if mtp_adaptive == 1
      # climb only after two consecutive full accepts, cap 4: chain
      # acceptance ~0.79^k can't pay for wider verifies past that
      if a == d
        mtp_streak[0] = mtp_streak[0] + 1
        if mtp_streak[0] >= 2 && d < 4
          mtp_d_cur[0] = d + 1
          mtp_streak[0] = 0
      else
        mtp_streak[0] = 0
        mtp_d_cur[0] = a > 1 ? a : 1
    cur = preds[a]
    pos = pos + n_keep
    round_ms.push(ccall("__w_clock_ms") - rt0)
else
  while ids.size() < n_generate
    rt0 = ccall("__w_clock_ms")
    pred = forward(pred, pos, true)
    if mtp_depth > 0
      if mtp_pending[0] >= 0
        mtp_total[0] = mtp_total[0] + 1
        if mtp_pending[0] == pred then mtp_hits[0] = mtp_hits[0] + 1
      mtp_pending[0] = mtp_step(pred, pos + 1, 0)
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
if mtp_spec > 0 && spec_rounds > 0
  line = "mtp spec depth " + (mtp_adaptive == 1 ? "adaptive" : mtp_spec.to_s) + ": " + spec_rounds.to_s + " rounds, accepted-drafts histogram "
  ai = 0
  while ai <= 7
    line = line + ai.to_s + ":" + accept_hist[ai].to_s + " "
    ai = ai + 1
  << line
if mtp_depth > 0 && mtp_total[0] > 0
  << "mtp draft acceptance: " + mtp_hits[0].to_s + "/" + mtp_total[0].to_s + " = " + (100.0 * mtp_hits[0] / mtp_total[0]).to_s + "% (harness adds a draft to every round; tok/s above is NOT representative)"

if multi_n > 0
  << "---- width-" + multi_n.to_s + " multi verify: serial ids are the oracle ----"
  reset_states
  i = 0
  while i < prompt.size()
    forward(prompt[i], i, i == prompt.size() - 1)
    i = i + 1
  base = 0
  mpos = prompt.size()
  mismatches = 0
  mrounds = []
  mt0 = ccall("__w_clock_ms")
  while base + 1 < ids.size()
    bn = ids.size() - 1 - base
    if bn > multi_n then bn = multi_n
    block = []
    bi = 0
    while bi < bn
      block.push(ids[base + bi])
      bi = bi + 1
    rt = ccall("__w_clock_ms")
    preds = forward_multi(block, mpos, bn)
    mrounds.push(ccall("__w_clock_ms") - rt)
    bi = 0
    while bi < bn
      if preds[bi] != ids[base + bi + 1]
        mismatches = mismatches + 1
        if mismatches <= 5
          << "MISMATCH at oracle index " + (base + bi + 1).to_s + ": multi " + preds[bi].to_s + " vs serial " + ids[base + bi + 1].to_s
      bi = bi + 1
    base = base + bn
    mpos = mpos + bn
  m_elapsed = ccall("__w_clock_ms") - mt0
  msorted = mrounds.sort()
  mmed = msorted.size() > 0 ? msorted[msorted.size() / 2] : ~1.0
  if mismatches == 0
    << "MULTI EXACT: " + base.to_s + " tokens verified in width-" + multi_n.to_s + " blocks, 0 mismatches"
  else
    << "MULTI FAILED: " + mismatches.to_s + " mismatches over " + base.to_s + " tokens"
  << "multi rounds: median " + mmed.to_s + " ms per block of " + multi_n.to_s + " = " + (1000.0 * multi_n / mmed).to_s + " tok/s if fully accepted (" + base.to_s + " tokens in " + m_elapsed.to_s + " ms)"
