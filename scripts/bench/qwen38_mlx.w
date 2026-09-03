# Decode-only Qwen3.8 27B MLX/NVFP4 inference on Metal.
#
# Prepare the Ollama weights without copying them:
#   ruby scripts/bench/prepare_ollama_mlx.rb qwen3.8:27b-mlx
#
# Run modes:
#   bin/tungsten run scripts/bench/qwen38_mlx.w baseline 8
#   bin/tungsten run scripts/bench/qwen38_mlx.w optimized 8
#   bin/tungsten run scripts/bench/qwen38_mlx.w concurrent 8
#   bin/tungsten run scripts/bench/qwen38_mlx.w mtp 24
#   bin/tungsten run scripts/bench/qwen38_mlx.w mtp2 24
#   bin/tungsten run scripts/bench/qwen38_mlx.w mtp-auto 48
#   bin/tungsten run scripts/bench/qwen38_mlx.w concurrent 8 auto mmap
#
# All modes execute the same f32 compute graph. Optimized mode fuses dense
# gate/up and projection+residual operations and submits one command buffer
# per token; concurrent mode additionally overlaps independent projections.
# MTP mode uses the checkpoint's one-layer MTP head to draft one token and a
# two-token target pass that shares each packed weight load across both rows.
# MTP-auto probes the one- and two-draft arms on complete decode rounds and
# retains the one with the higher observed emitted-token rate.
# Draft selection projects only the common-token prefix plus Qwen control
# tokens; verification still scores the full vocabulary and remains exact.

use core/metal
use core/json
use tungsten-llama/sharded_safetensors
use tungsten-llama/tokenizer

MODEL_INDEX = "/Users/erik/.cache/tungsten/qwen3.8-27b-mlx/model.safetensors.index.json"
TOKENIZER_BIN = "/Users/erik/.cache/tungsten/qwen3.8-27b-mlx/tokenizer.json.bin"
NVFP4_DIR = "bits/tungsten-llama/lib/kernels/nvfp4/"
SHARED_DIR = "bits/tungsten-llama/lib/kernels/shared/"
QWEN_DIR = "bits/tungsten-llama/lib/kernels/qwen3_6/"

HIDDEN = 5120
N_LAYERS = 64
N_VOCAB = 248320
FFN = 17408
EPS = ~0.000001

# Linear attention / GatedDeltaNet.
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
N_KV_HEADS = 4
HEAD_DIM = 256
GQA = N_HEADS / N_KV_HEADS
KV_DIM = N_KV_HEADS * HEAD_DIM
ATTN_DIM = N_HEADS * HEAD_DIM
QFULL_DIM = ATTN_DIM * 2
ATTN_SCALE = ~1.0 / Math.sqrt(~0.0 + HEAD_DIM)
ROT_DIM = 64
ROT_HALF = ROT_DIM / 2
ROPE_BASE = ~10000000.0
MTP_DRAFT_PREFIX = 98304
MTP_DRAFT_CONTROL_START = 248044
MTP_DRAFT_CONTROL_COUNT = 26
MTP_DRAFT_CONTROL_ROWS = 32
ARGMAX_CHUNKS = (N_VOCAB + 1023) / 1024

mode = ARGV.size() > 0 ? ARGV[0] : "concurrent"
n_generate = ARGV.size() > 1 ? ARGV[1].to_i() : 8
row_schedule = ARGV.size() > 2 ? ARGV[2] : (mode == "concurrent" ? "16r" : "r2")
weight_binding = ARGV.size() > 3 ? ARGV[3] : "mmap"
force_reject = ARGV.size() > 4 && ARGV[4] == "force-reject"
legacy_mtp = ARGV.size() > 4 && ARGV[4] == "legacy-mtp"
full_history_mtp = ARGV.size() > 4 && ARGV[4] == "full-history"
full_draft_vocab = legacy_mtp || (ARGV.size() > 4 && ARGV[4] == "full-draft-vocab")
profile_components = ARGV.size() > 4 && ARGV[4] == "profile"
profile_prompt_tokens = ARGV.size() > 5 ? ARGV[5].to_i() : 5
triplet_variant = ARGV.size() > 6 ? ARGV[6] : "auto"
# A full MTLBarrierScopeBuffers barrier drains EVERY outstanding buffer write on
# the encoder. There are ~620 of them in one width-3 verify, which is most of the
# gap between the verify's measured 36.5 ms and its ~26 ms weight-streaming
# floor. Apple documents memoryBarrierWithResources as cheaper when only a few
# buffers carry the RAW dependency -- which is true at every site below, where
# the dependency is one or two named scratch buffers. "fullbar" restores the old
# behaviour so the change stays measurable.
scoped_barriers = !(ARGV.size() > 6 && ARGV[6] == "fullbar")
fast_draft_select = !(ARGV.size() > 6 && ARGV[6] == "slowsel")
if ARGV.size() > 6 && ARGV[6] == "slowsel" then triplet_variant = "auto"
if ARGV.size() > 6 && ARGV[6] == "fullbar" then triplet_variant = "auto"
# Diagnostic: histogram the rank of the target's token in the head's draft
# distribution. Decides whether tree drafting can pay -- see mtp_draft_rank.metal.
draft_rank_probe = ARGV.size() > 7 && ARGV[7] == "rank-probe"
row_scan = ARGV.size() > 7 && (ARGV[7] == "row-scan" || ARGV[7] == "row-scan-multi")
# Runtime-width block verify (decode_multi.metal): one causal pass over n <= 8
# rows with tape-replay rollback. ARGV[7] = "multi" swaps it in for the quad
# and triplet verifies so ids/acceptance can be diffed against them;
# "row-scan-multi" times widths 1..8. ARGV[8] then selects the NVFP4 kernel
# rung ("auto" | r1 | r2 | r4 | s1 | s2 | s4; s = split-hoist, b6/b8 only).
# dflash2: block-diffusion drafter (z-lab DFlash2) + width-n exact verify.
# ARGV[7] = "b<k>" sets the block width (anchor + k-1 drafts, k <= 8; default
# 8); ARGV[8] the NVFP4 verify rung as for "multi".
dflash2_enabled = mode == "dflash2"
dflash2_block = 8
# A trailing "q" on the block spec ("b8q") selects the NVFP4-quantized drafter
# (scripts in ~/src/dflash-gate0/quantize_dflash2.py) instead of the bf16 one.
draft_quant = false
if dflash2_enabled && ARGV.size() > 7 && ARGV[7].size() > 1 && ARGV[7].slice(0, 1) == "b"
  bspec = ARGV[7]
  if bspec.slice(bspec.size() - 1, 1) == "q"
    draft_quant = true
    bspec = bspec.slice(0, bspec.size() - 1)
  dflash2_block = bspec.slice(1, bspec.size() - 1).to_i()
if dflash2_block < 2 || dflash2_block > 8 then raise "dflash2 block width must be 2..8"
# GEMM prefill (plan phase 2): ARGV[6] = "gemm-prefill" runs the prompt through
# the backbone in chunks of up to 64 rows, one weight stream per chunk, on the
# simdgroup-matrix NVFP4 GEMM (f32 accumulate, global scale; not bit-exact vs
# serial -- gate it on ids). Only the last row's logits are computed, through
# the serial lm_head path.
prefill_gemm = ARGV.size() > 6 && ARGV[6] == "gemm-prefill"
if prefill_gemm then triplet_variant = "auto"
# K/V cache capacity in positions. gemm-prefill exists to run long prompts, so
# it gets 2048; every other mode keeps the 640 that the decode-path
# pair/triplet/quad SDPA kernels are compiled for (their score arrays are
# threadgroup-static at 640 and truncate silently past it).
MAX_POS = prefill_gemm ? 2048 : 640
# decode_multi.metal's block-verify SDPA holds its scores in a threadgroup
# array of MULTI_MAX_DECODE_POS floats and clamps `usable` to it -- past that
# the attention SILENTLY drops the oldest positions and every reported number
# stays plausible. It is a hard ceiling on prompt + generate.
SDPA_MULTI_MAX_POS = 2051
if prefill_gemm && devchain then raise "gemm-prefill replaces the devchain triplet prefill; drop devchain"
multi_verify = dflash2_enabled || prefill_gemm || (ARGV.size() > 7 && (ARGV[7] == "multi" || ARGV[7] == "row-scan-multi"))
multi_variant = (multi_verify && ARGV.size() > 8) ? ARGV[8] : "auto"
if dflash2_enabled && ARGV.size() > 7 && ARGV[7] == "devchain" then raise "dflash2 has its own device chain; drop devchain"
# Single-sync speculative round: keep the depth-2 chained draft's argmax on
# device and read it only after the verify (one GPU sync/round instead of
# two). Pure scheduling -- ids and acceptance stay byte-identical. Default
# off; A/B it with `mtp2 ... devchain` in ARGV[7].
devchain = ARGV.size() > 7 && ARGV[7] == "devchain"
# Diagnostic: dump the five DFlash2 conditioning taps -- the residual stream
# after layers 5/19/33/47/61 (pre-final-norm, exactly what the drafter's
# `fc` consumes) -- for every position of a SERIAL greedy run, plus the token
# stream, so the reference DFlash2 drafter can be scored offline on THIS
# engine's NVFP4 hidden states. Gate 0 of the DFlash2 port: if the drafter
# cannot read our taps, no kernel is worth writing. Serial path only (mode
# `concurrent`); ARGV[8] is the output path prefix (.f32 + .json).
tapdump = ARGV.size() > 7 && ARGV[7] == "tapdump"
tapdump_prefix = ARGV.size() > 8 ? ARGV[8] : "/tmp/qwen38_taps"
tap_layers = [5, 19, 33, 47, 61]
# Optional ARGV[9]: a JSON file holding the prompt token ids verbatim (e.g. a
# chat-templated prompt built elsewhere), replacing the prose fixture.
prompt_ids_file = ARGV.size() > 9 ? ARGV[9] : ""
# ARGV[10] = "probe:<prefix>" (dflash2): dump round 0's draft hidden, top-16
# candidates/unaries and draft ids to <prefix>.* for comparison against the
# reference drafter run on the same taps.
dflash2_probe = ""
if ARGV.size() > 10 && ARGV[10].size() > 6 && ARGV[10].slice(0, 6) == "probe:"
  dflash2_probe = ARGV[10].slice(6, ARGV[10].size() - 6)
# Async decode-phase history appends (devchain): a want_draft=false MTP
# step writes only KV, so it needs no host value -- commit it async and let
# the round's next sync drain it. Handles are released at round end. Sized
# for the max history appends in one decode round (3 at depth 3).
hist_cbs = [0, 0, 0, 0]
if multi_verify && devchain then raise "multi verify and devchain are not combinable yet"
hist_cb_n = [0]
prose_tech = ARGV.size() > 4 && ARGV[4] == "prose-tech"
rank_hist = [0, 0, 0, 0, 0, 0]
rank_outside = 0
rank_samples = 0
legacy_reductions = ARGV.size() > 6 && ARGV[6] == "legacy-reductions"
if profile_prompt_tokens < 1 then raise "profile prompt length must be positive"
# The K/V caches are fixed at MAX_POS rows, and overflowing them does NOT
# fault -- it silently wraps and the model emits fluent-looking garbage while
# every reported number (tok/s, acceptance) stays plausible. Fail loudly
# instead: a benchmark that lies quietly is worse than one that stops.
if profile_prompt_tokens + n_generate > MAX_POS
  raise "prompt " + profile_prompt_tokens.to_s + " + generate " + n_generate.to_s + " exceeds MAX_POS " + MAX_POS.to_s + "; the K/V cache would wrap and the run would report plausible numbers for garbage output"
if prefill_gemm && profile_prompt_tokens + n_generate > SDPA_MULTI_MAX_POS
  raise "prompt " + profile_prompt_tokens.to_s + " + generate " + n_generate.to_s + " exceeds the block-verify SDPA ceiling " + SDPA_MULTI_MAX_POS.to_s + " (decode_multi.metal MULTI_MAX_DECODE_POS); attention would silently truncate"
setup_t0 = ccall("__w_clock_ms")
# Mutable profiling state (closure-local assignment would shadow scalars):
# phase, decode target ms/count, prefill target ms/count, verify ms/count,
# draft ms/count, history ms/count, hidden-copy ms/count, rollback ms/count,
# first-prefill ms, remaining-prefill ms.
profile_stats = [0, ~0.0, 0, ~0.0, 0, ~0.0, 0, ~0.0, 0,
  ~0.0, 0, ~0.0, 0, ~0.0, 0, ~0.0, ~0.0]
optimized = mode == "optimized" || mode == "concurrent"
concurrent = mode == "concurrent"
mtp_enabled = mode == "mtp" || mode == "mtp2" || mode == "mtp-auto" || mode == "mtp3"
mtp_adaptive = mode == "mtp-auto"
# mtp3 drafts three tokens and verifies FOUR target rows in one causal pass.
# It reuses the depth-2 machinery for everything except the verify width, so
# mtp/mtp2 are byte-for-byte unaffected by its presence.
mtp_depth3 = mode == "mtp3"
mtp_depth2 = mode == "mtp2" || mtp_adaptive || mtp_depth3
if dflash2_enabled
  optimized = true
  concurrent = true
if mtp_enabled
  optimized = true
  concurrent = true
if !optimized && mode != "baseline"
  raise "usage: qwen38_mlx.w [baseline|optimized|concurrent|mtp|mtp2|mtp-auto] [tokens] [4r|8r|16r|r2|auto] [mmap|copy]"
if row_schedule != "4r" && row_schedule != "8r" && row_schedule != "16r" && row_schedule != "r2" && row_schedule != "auto"
  raise "row schedule must be 4r, 8r, 16r, r2, or auto"
if weight_binding != "copy" && weight_binding != "mmap"
  raise "weight binding must be copy or mmap"

device = metal_device()
queue = metal_queue(device)
st = Tungsten:Llama:ShardedSafetensors.new(MODEL_INDEX)

<< "qwen3.8/27b-mlx: " + mode + ", " + row_schedule + ", " + weight_binding + ", " + st.count().to_s + " tensors"

# Compile reusable pipelines.
bf16_embed_pipe = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "bf16_embedding_lookup.metal")), "bf16_embedding_lookup")
bf16_matvec_pipe = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "bf16_matvec.metal")), "bf16_matvec")
rms_pipe = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "rms_norm.metal")), "rms_norm")
rms_batch_pipe = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "rms_norm_batch.metal")), "rms_norm_batch")
phn_pipe = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "per_head_norm.metal")), "per_head_norm")
copy_pipe = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "copy_f32_slice.metal")), "copy_f32_slice")
copy_i32_at_pipe = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "copy_i32_at.metal")), "copy_i32_at")
copy_f32_at_pipe = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "copy_f32_at.metal")), "copy_f32_at")
bf16_embed_buf_pipe = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "bf16_embedding_lookup_buf.metal")), "bf16_embedding_lookup_buf")
kv_write_pipe = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "kv_write.metal")), "kv_write")
add_pipe = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "residual_add.metal")), "residual_add")
silu_pipe = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "silu_mul.metal")), "silu_mul")

# --- Neural-Accelerator (matmul2d) prefill path (gemm-prefill only) ---
# The "na" kernels take plain device pointers and build their tensor views
# in-shader, so they dispatch from the CLASSIC compute encoder straight into
# forward_multi's single concurrent command buffer: no Metal-4 argument table,
# command buffer, allocator or residency set, and -- the point -- no commit
# segmentation. The MTL4 predecessor cost five blocking GPU round-trips per
# layer. See docs/na-classic-encoder-2026-09-02.md.
NA_DIR = "bits/tungsten-llama/lib/kernels/na/"
NA_MT = 128
NA_MT64 = 64
na_lib = metal_compile_source(device, read_file(NA_DIR + "nvfp4_matmul_na.metal"))
na_pipe = metal_pipeline(na_lib, "nvfp4_matmul_na")
na_m64_pipe = metal_pipeline(na_lib, "nvfp4_matmul_na_m64")
f32_to_f16_pipe = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "f32_to_f16.metal")), "f32_to_f16")
g_na_ffn = false
g_na_attn = false
argmax_pipe = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "argmax.metal")), "argmax")
argmax_parallel_lib = metal_compile_source(device, read_file(SHARED_DIR + "argmax_two_stage.metal"))
argmax_stage1_pipe = metal_pipeline(argmax_parallel_lib, "argmax_stage1")
argmax_stage2_pipe = metal_pipeline(argmax_parallel_lib, "argmax_stage2")

scaled_pipe = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_scaled.metal")), "nvfp4_matvec_mlx_scaled")
r2_pipe = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_scaled_r_2.metal")), "nvfp4_matvec_mlx_scaled_r_2")
scaled_rows_lib = metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_scaled_rows.metal"))
scaled_4_pipe = metal_pipeline(scaled_rows_lib, "nvfp4_matvec_mlx_scaled_4r")
scaled_16_pipe = metal_pipeline(scaled_rows_lib, "nvfp4_matvec_mlx_scaled_16r")
scaled_res_pipe = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_scaled_residual.metal")), "nvfp4_matvec_mlx_scaled_residual")
scaled_gu_pipe = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_scaled_gu.metal")), "nvfp4_matvec_mlx_scaled_gu")
scaled_pair_lib = metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_scaled_pair.metal"))
scaled_pair_pipe = metal_pipeline(scaled_pair_lib, "nvfp4_matvec_mlx_scaled_pair")
scaled_pair_res_pipe = metal_pipeline(scaled_pair_lib, "nvfp4_matvec_mlx_scaled_pair_residual")
scaled_triplet_lib = metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_scaled_triplet.metal"))
scaled_triplet_pipe = metal_pipeline(scaled_triplet_lib, "nvfp4_matvec_mlx_scaled_triplet")
scaled_triplet_res_pipe = metal_pipeline(scaled_triplet_lib, "nvfp4_matvec_mlx_scaled_triplet_residual")
scaled_triplet_r1_pipe = metal_pipeline(scaled_triplet_lib, "nvfp4_matvec_mlx_scaled_triplet_r1")
scaled_triplet_res_r1_pipe = metal_pipeline(scaled_triplet_lib, "nvfp4_matvec_mlx_scaled_triplet_residual_r1")
scaled_triplet_hoist_pipe = metal_pipeline(scaled_triplet_lib, "nvfp4_matvec_mlx_scaled_triplet_hoist")
scaled_triplet_res_hoist_pipe = metal_pipeline(scaled_triplet_lib, "nvfp4_matvec_mlx_scaled_triplet_residual_hoist")
# Cross-row wide verify (MLX qmv_fast_crossrow_affine4_g64_wide shape): ROWS
# output rows per SIMD group with the activations loaded ONCE and shared across
# them, instead of one output row re-issuing every activation load. Selectable
# as ARGV[6] = "b3" so the A/B against the hoisted triplet stays runnable.
scaled_wide_lib = metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_scaled_wide.metal"))
wide_b3_pipe = metal_pipeline(scaled_wide_lib, "nvfp4_wide_b3_r2")
wide_b3_res_pipe = metal_pipeline(scaled_wide_lib, "nvfp4_wide_b3_r2_residual")
# r4 (4 output rows per SIMD group) amortizes the shared activation loads over
# twice as many rows, which pays only where the activation working set is large
# relative to the weight tile: the bakeoff measured r4 at 1.21x r2 on mlp-down
# (K=17408) and a wash-to-loss everywhere K=5120. Split on that, and keep both
# reachable -- this is the axis with a known non-monotonic hole in it.
wide_b3_r4_pipe = metal_pipeline(scaled_wide_lib, "nvfp4_wide_b3_r4")
wide_b3_r4_res_pipe = metal_pipeline(scaled_wide_lib, "nvfp4_wide_b3_r4_residual")
# Width-4 verify (mtp3). Same r4-for-FFN / r2-elsewhere split the bakeoff
# measured at width 3; at width 4 the bakeoff margins are larger still
# (mlp-down 2.07x, lm-head 1.84x over the incumbent quad kernel).
wide_b4_pipe = metal_pipeline(scaled_wide_lib, "nvfp4_wide_b4_r2")
wide_b4_res_pipe = metal_pipeline(scaled_wide_lib, "nvfp4_wide_b4_r2_residual")
wide_b4_r4_pipe = metal_pipeline(scaled_wide_lib, "nvfp4_wide_b4_r4")
wide_b4_r4_res_pipe = metal_pipeline(scaled_wide_lib, "nvfp4_wide_b4_r4_residual")
# Half-footprint width-4 (8 K-values per lane). Cuts the hoisted activation
# register footprint from 64 floats to 32, which is what the +9 ms marginal at
# row 4 was paying for.
wide_b4h_pipe = metal_pipeline(scaled_wide_lib, "nvfp4_wideh_b4_r2")
wide_b4h_res_pipe = metal_pipeline(scaled_wide_lib, "nvfp4_wideh_b4_r2_residual")

conv_pipe = metal_pipeline(metal_compile_source(device, read_file(QWEN_DIR + "conv1d_depthwise_step.metal")), "conv1d_depthwise_step")
g_pipe = metal_pipeline(metal_compile_source(device, read_file(QWEN_DIR + "compute_g.metal")), "compute_g")
delta_pipe = metal_pipeline(metal_compile_source(device, read_file(QWEN_DIR + "gated_delta_step.metal")), "gated_delta_step")
rng_pipe = metal_pipeline(metal_compile_source(device, read_file(QWEN_DIR + "rms_norm_gated.metal")), "rms_norm_gated")
sigmoid_pipe = metal_pipeline(metal_compile_source(device, read_file(QWEN_DIR + "sigmoid_inplace.metal")), "sigmoid_f32")
split_pipe = metal_pipeline(metal_compile_source(device, read_file(QWEN_DIR + "split_q_gate.metal")), "split_q_gate")
rope_pipe = metal_pipeline(metal_compile_source(device, read_file(QWEN_DIR + "partial_rope_neox.metal")), "partial_rope_neox")
sdpa_pipe = metal_pipeline(metal_compile_source(device, read_file(QWEN_DIR + "sdpa_decode_hd256.metal")), "sdpa_decode_hd256")
gate_pipe = metal_pipeline(metal_compile_source(device, read_file(QWEN_DIR + "attn_output_gate.metal")), "attn_output_gate")

pair_lib = metal_compile_source(device, read_file(QWEN_DIR + "decode_pair.metal"))
pair_embed_pipe = metal_pipeline(pair_lib, "bf16_embedding_lookup_pair")
pair_bf16_pipe = metal_pipeline(pair_lib, "bf16_matvec_pair")
concat_pipe = metal_pipeline(pair_lib, "concat_f32")
copy_pair_row_pipe = metal_pipeline(pair_lib, "copy_pair_row")
copy_pair_slice_pipe = metal_pipeline(pair_lib, "copy_f32_slice_pair")
split_pair_pipe = metal_pipeline(pair_lib, "split_q_gate_pair")
phn_rope_pair_pipe = metal_pipeline(pair_lib, "per_head_norm_partial_rope_pair")
kv_write_pair_pipe = metal_pipeline(pair_lib, "kv_write_pair")
sdpa_pair_pipe = metal_pipeline(pair_lib, "sdpa_decode_pair_hd256")
conv_pair_pipe = metal_pipeline(pair_lib, "conv1d_depthwise_pair")
delta_pair_pipe = metal_pipeline(pair_lib, "gated_delta_pair")

triplet_lib = metal_compile_source(device, read_file(QWEN_DIR + "decode_triplet.metal"))
triplet_embed_pipe = metal_pipeline(triplet_lib, "bf16_embedding_lookup_triplet")
triplet_bf16_pipe = metal_pipeline(triplet_lib, "bf16_matvec_triplet")
copy_triplet_slice_pipe = metal_pipeline(triplet_lib, "copy_f32_slice_triplet")
split_triplet_pipe = metal_pipeline(triplet_lib, "split_q_gate_triplet")
phn_rope_triplet_pipe = metal_pipeline(triplet_lib, "per_head_norm_partial_rope_triplet")
kv_write_triplet_pipe = metal_pipeline(triplet_lib, "kv_write_triplet")
sdpa_triplet_pipe = metal_pipeline(triplet_lib, "sdpa_decode_triplet_hd256")
conv_triplet_pipe = metal_pipeline(triplet_lib, "conv1d_depthwise_triplet")
delta_triplet_pipe = metal_pipeline(triplet_lib, "gated_delta_triplet")

mtp_select_lib = metal_compile_source(device, read_file(QWEN_DIR + "mtp_draft_select.metal"))
mtp_select_pipe = metal_pipeline(mtp_select_lib, "mtp_compact_draft_select")
# Tiled replacement for the single-simdgroup draft argmax. ARGV[6]="slowsel"
# keeps the old kernel so the change stays measurable.
mtp_select_fast_lib = metal_compile_source(device, read_file(QWEN_DIR + "mtp_draft_select_fast.metal"))
mtp_sel1_pipe = metal_pipeline(mtp_select_fast_lib, "mtp_draft_select_stage1")
mtp_sel2_pipe = metal_pipeline(mtp_select_fast_lib, "mtp_draft_select_stage2")
MTP_SEL_TILES = (MTP_DRAFT_PREFIX + MTP_DRAFT_CONTROL_COUNT + 1023) / 1024
mtp_sel_vals = metal_buffer(device, MTP_SEL_TILES * 4)
mtp_sel_ids = metal_buffer(device, MTP_SEL_TILES * 4)
mtp_rank_lib = metal_compile_source(device, read_file(QWEN_DIR + "mtp_draft_rank.metal"))
mtp_rank_pipe = metal_pipeline(mtp_rank_lib, "mtp_draft_target_rank")

rms_pair_lib = metal_compile_source(device, read_file(SHARED_DIR + "rms_norm_batch_fc.metal"))
rms_pair_pipe = metal_pipeline_with_int_constants(rms_pair_lib, "rms_norm_batch_fc", [HIDDEN, 2])
argmax_pair_lib = metal_compile_source(device, read_file(SHARED_DIR + "argmax_batch_fc.metal"))
argmax_pair_pipe = metal_pipeline_with_int_constants(argmax_pair_lib, "argmax_batch_fc", [N_VOCAB, 2])
rms_triplet_pipe = metal_pipeline_with_int_constants(rms_pair_lib, "rms_norm_batch_fc", [HIDDEN, 3])
quad_lib = metal_compile_source(device, read_file(QWEN_DIR + "decode_quad.metal"))
quad_embed_pipe = metal_pipeline(quad_lib, "bf16_embedding_lookup_quad")
quad_bf16_pipe = metal_pipeline(quad_lib, "bf16_matvec_quad")
copy_quad_slice_pipe = metal_pipeline(quad_lib, "copy_f32_slice_quad")
split_quad_pipe = metal_pipeline(quad_lib, "split_q_gate_quad")
phn_rope_quad_pipe = metal_pipeline(quad_lib, "per_head_norm_partial_rope_quad")
kv_write_quad_pipe = metal_pipeline(quad_lib, "kv_write_quad")
sdpa_quad_pipe = metal_pipeline(quad_lib, "sdpa_decode_quad_hd256")
conv_quad_pipe = metal_pipeline(quad_lib, "conv1d_depthwise_quad")
delta_quad_pipe = metal_pipeline(quad_lib, "gated_delta_quad")
rms_quad_pipe = metal_pipeline_with_int_constants(rms_pair_lib, "rms_norm_batch_fc", [HIDDEN, 4])
argmax_quad_pipe = metal_pipeline_with_int_constants(argmax_pair_lib, "argmax_batch_fc", [N_VOCAB, 4])
argmax_triplet_pipe = metal_pipeline_with_int_constants(argmax_pair_lib, "argmax_batch_fc", [N_VOCAB, 3])

# ---- runtime-width block verify (n <= MULTI_MAX rows in one causal pass) ----
# The gemm-prefill chunk width IS the M of every prefill GEMM. The Neural
# Accelerators need M >= 512 to reach their ~53 TFLOPS plateau (crossover vs
# the simdgroup ladder is M ~= 48-64), so the chunk is 512 by default.
# PREFILL_CHUNK overrides it, which is what keeps the pre-NA 64-row arm
# runnable for A/Bs. It must be 64 or a multiple of the 128-row NA tile: the
# cooperative-tensor store does not clip, so a chunk that is not tile-aligned
# would let na_proj round a width up past the scratch buffers' row count.
prefill_chunk_env = ccall("__w_env", "PREFILL_CHUNK")
PREFILL_CHUNK = prefill_chunk_env == nil ? 512 : prefill_chunk_env.to_i()
if PREFILL_CHUNK != 64 && (PREFILL_CHUNK < 128 || PREFILL_CHUNK % 128 != 0)
  raise "PREFILL_CHUNK must be 64 or a multiple of 128, got " + PREFILL_CHUNK.to_s
MULTI_MAX = prefill_gemm ? PREFILL_CHUNK : 8
MULTI_WIDE_MAX = 8
# Only the VERIFY reads whole logit rows, and it is never wider than the
# speculative block. Sizing the logits scratch by MULTI_MAX would cost 508 MB
# at chunk 512 for eight rows of use.
LOGITS_MULTI_MAX = 8
# The simdgroup-matrix GEMM ladder tops out at 64 rows (nvfp4_gemm_f32's
# widest tile is MT=8 x 8 rows). Wider chunks go to the Neural Accelerators.
MULTI_LADDER_MAX = 64
multi_pipes = {}
multi_rows = {}
if multi_verify
  multi_lib = metal_compile_source(device, read_file(QWEN_DIR + "decode_multi.metal"))
  multi_embed_pipe = metal_pipeline(multi_lib, "bf16_embedding_lookup_multi")
  multi_bf16_pipe = metal_pipeline(multi_lib, "bf16_matvec_multi")
  copy_multi_slice_pipe = metal_pipeline(multi_lib, "copy_f32_slice_multi")
  copy_taps_multi_pipe = metal_pipeline(multi_lib, "copy_taps_multi")
  split_multi_pipe = metal_pipeline(multi_lib, "split_q_gate_multi")
  phn_rope_multi_pipe = metal_pipeline(multi_lib, "per_head_norm_partial_rope_multi")
  kv_write_multi_pipe = metal_pipeline(multi_lib, "kv_write_multi")
  sdpa_multi_pipe = metal_pipeline(multi_lib, "sdpa_decode_multi_hd256")
  conv_multi_pipe = metal_pipeline(multi_lib, "conv1d_depthwise_multi")
  conv_replay_pipe = metal_pipeline(multi_lib, "conv_state_replay")
  delta_multi_pipe = metal_pipeline(multi_lib, "gated_delta_multi")
  # The NVFP4 rung table: key "b<n>_<rung>[_res]" -> pipeline, rows per SIMD group.
  bw = 1
  while bw <= MULTI_WIDE_MAX
    rr = 0
    while rr < 3
      rung = rr == 0 ? 1 : (rr == 1 ? 2 : 4)
      res = 0
      while res < 2
        kname = "nvfp4_wide_b" + bw.to_s + "_r" + rung.to_s + (res == 1 ? "_residual" : "")
        key = "b" + bw.to_s + "_r" + rung.to_s + (res == 1 ? "_res" : "")
        multi_pipes[key] = metal_pipeline(scaled_wide_lib, kname)
        multi_rows[key] = rung
        res = res + 1
      rr = rr + 1
    bw = bw + 1
  gemm_lib = metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_gemm_f32.metal"))
  gemm_tiles = [["m8", 8], ["m16", 16], ["m32", 32], ["m64", 64]]
  gi = 0
  while gi < gemm_tiles.size()
    gt = gemm_tiles[gi]
    gp = metal_pipeline(gemm_lib, "nvfp4_gemm_f32_" + gt[0])
    gpr = metal_pipeline(gemm_lib, "nvfp4_gemm_f32_" + gt[0] + "_residual")
    lo = gi == 0 ? 1 : gemm_tiles[gi - 1][1] + 1
    bw = lo
    while bw <= gt[1] && bw <= MULTI_MAX
      multi_pipes["b" + bw.to_s + "_g"] = gp
      multi_pipes["b" + bw.to_s + "_g_res"] = gpr
      multi_rows["b" + bw.to_s + "_g"] = 0
      multi_rows["b" + bw.to_s + "_g_res"] = 0
      bw = bw + 1
    gi = gi + 1
  split_specs = [["b8_s1", "nvfp4_wides_b8_r1", 1], ["b8_s2", "nvfp4_wides_b8_r2", 2],
    ["b8_s4", "nvfp4_wides_b8_r4", 4], ["b6_s2", "nvfp4_wides_b6_r2", 2]]
  si = 0
  while si < split_specs.size()
    sp = split_specs[si]
    multi_pipes[sp[0]] = metal_pipeline(scaled_wide_lib, sp[1])
    multi_rows[sp[0]] = sp[2]
    multi_pipes[sp[0] + "_res"] = metal_pipeline(scaled_wide_lib, sp[1] + "_residual")
    multi_rows[sp[0] + "_res"] = sp[2]
    si = si + 1
if dflash2_enabled
  draft_lib = metal_compile_source(device, read_file(QWEN_DIR + "dflash2_draft.metal"))
  bf16_wide_r2_pipe = metal_pipeline(draft_lib, "bf16_wide_multi_r2")
  dyn_conv_pipe = metal_pipeline(draft_lib, "dyn_conv_apply")
  dyn_conv_res_pipe = metal_pipeline(draft_lib, "dyn_conv_apply_residual")
  sdpa_draft_pipe = metal_pipeline(draft_lib, "sdpa_draft_hd128")
  topk_pipe = metal_pipeline(draft_lib, "topk16_rows")
  selector_pipe = metal_pipeline(draft_lib, "selector_walk")

# Small weight-loading helpers. Quantized handles are [packed, group scale,
# global scale]. Each tensor binds a byte-offset view of its shard's mmap, so
# the GPU reads the file-backed pages directly without expanding or copying.
-> raw_tensor(name)
  d = st.tensor(name)
  if weight_binding == "mmap"
    metal_buffer_for_mmap(device, st.mmap_for(name), d[:byte_offset], d[:byte_length])
  else
    metal_buffer_for(device, st.mmap_for(name).view_at(d[:byte_offset], :u8, d[:byte_length]))

-> raw_tensor_rows(spec)
  name = spec[0]
  row_start = spec[1]
  row_count = spec[2]
  d = st.tensor(name)
  total_rows = d[:shape][0]
  row_bytes = d[:byte_length] / total_rows
  byte_offset = d[:byte_offset] + row_start * row_bytes
  byte_length = row_count * row_bytes
  if weight_binding == "mmap"
    metal_buffer_for_mmap(device, st.mmap_for(name), byte_offset, byte_length)
  else
    metal_buffer_for(device, st.mmap_for(name).view_at(byte_offset, :u8, byte_length))

-> quant_tensor(name)
  [raw_tensor(name), raw_tensor(name + ".scale"), raw_tensor(name + ".global_scale")]

-> quant_tensor_rows(spec)
  name = spec[0]
  row_start = spec[1]
  row_count = spec[2]
  [raw_tensor_rows([name, row_start, row_count]),
   raw_tensor_rows([name + ".scale", row_start, row_count]),
   raw_tensor(name + ".global_scale")]

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

# Qwen3.5 checkpoints carrying MTP weights store the outer RMSNorm, q_norm,
# and k_norm parameters as deltas from one. This mirrors mlx-lm's sanitize().
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

# Embedding and fixed final weights.
embed_w = raw_tensor("model.language_model.embed_tokens.weight")
final_norm = metal_buffer(device, HIDDEN * 4)
load_shifted_norm(["model.language_model.norm.weight", HIDDEN, final_norm])
lm_head = quant_tensor("lm_head.weight")
mtp_draft_prefix_head = quant_tensor_rows(
  ["lm_head.weight", 0, MTP_DRAFT_PREFIX])
mtp_draft_control_head = quant_tensor_rows(
  ["lm_head.weight", MTP_DRAFT_CONTROL_START, MTP_DRAFT_CONTROL_ROWS])

# Per-head constants used by GatedDeltaNet's q/k normalization.
q_norm_scale = metal_buffer(device, DK * 4)
k_norm_scale = metal_buffer(device, DK * 4)
inv_sqrt_dk = ~1.0 / Math.sqrt(~0.0 + DK)
i = 0
while i < DK
  metal_buffer_write_f32(q_norm_scale, i, inv_sqrt_dk * inv_sqrt_dk)
  metal_buffer_write_f32(k_norm_scale, i, inv_sqrt_dk)
  i = i + 1

# Preload all handles and persistent recurrent/cache state.
layers = []
li = 0
while li < N_LAYERS
  prefix = "model.language_model.layers." + li.to_s + "."
  if (li % 8) == 0 then << "  loading layer " + li.to_s
  in_norm = metal_buffer(device, HIDDEN * 4)
  post_norm = metal_buffer(device, HIDDEN * 4)
  load_shifted_norm([prefix + "input_layernorm.weight", HIDDEN, in_norm])
  load_shifted_norm([prefix + "post_attention_layernorm.weight", HIDDEN, post_norm])
  base = {
    in_norm: in_norm,
    post_norm: post_norm,
    gate: quant_tensor(prefix + "mlp.gate_proj.weight"),
    up: quant_tensor(prefix + "mlp.up_proj.weight"),
    down: quant_tensor(prefix + "mlp.down_proj.weight")
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
    base[:qkv] = quant_tensor(prefix + "linear_attn.in_proj_qkv.weight")
    base[:z] = quant_tensor(prefix + "linear_attn.in_proj_z.weight")
    base[:a] = raw_tensor(prefix + "linear_attn.in_proj_a.weight")
    base[:b] = raw_tensor(prefix + "linear_attn.in_proj_b.weight")
    base[:conv] = conv_w
    base[:alog] = alog
    base[:dtb] = dtb
    base[:linear_norm] = ln_w
    base[:out] = quant_tensor(prefix + "linear_attn.out_proj.weight")
    base[:cs_a] = metal_buffer(device, 3 * QKV_DIM * 4)
    base[:cs_b] = metal_buffer(device, 3 * QKV_DIM * 4)
    base[:ss_a] = metal_buffer(device, HV * DV * DK * 4)
    base[:ss_b] = metal_buffer(device, HV * DV * DK * 4)
    if mtp_enabled
      base[:cs_mid] = metal_buffer(device, 3 * QKV_DIM * 4)
      base[:ss_mid] = metal_buffer(device, HV * DV * DK * 4)
      if mtp_depth2
        base[:cs_mid2] = metal_buffer(device, 3 * QKV_DIM * 4)
        base[:ss_mid2] = metal_buffer(device, HV * DV * DK * 4)
      if mtp_depth3
        base[:cs_mid3] = metal_buffer(device, 3 * QKV_DIM * 4)
        base[:ss_mid3] = metal_buffer(device, HV * DV * DK * 4)
    base[:ping] = 0
    if multi_verify
      # Per-layer copies of the recurrent inputs the width-n verify consumed,
      # so the rollback can replay the accepted prefix after every layer has
      # run (a shared scratch would already hold the next layer's rows).
      base[:qkv_m] = metal_buffer(device, MULTI_MAX * QKV_DIM * 4)
      base[:mq_m] = metal_buffer(device, MULTI_MAX * Q_DIM * 4)
      base[:mk_m] = metal_buffer(device, MULTI_MAX * K_DIM * 4)
      base[:mv_m] = metal_buffer(device, MULTI_MAX * V_DIM * 4)
      base[:g_m] = metal_buffer(device, MULTI_MAX * HV * 4)
      base[:beta_m] = metal_buffer(device, MULTI_MAX * HV * 4)
  else
    qn = metal_buffer(device, HEAD_DIM * 4)
    kn = metal_buffer(device, HEAD_DIM * 4)
    load_shifted_norm([prefix + "self_attn.q_norm.weight", HEAD_DIM, qn])
    load_shifted_norm([prefix + "self_attn.k_norm.weight", HEAD_DIM, kn])
    base[:kind] = "full"
    base[:q] = quant_tensor(prefix + "self_attn.q_proj.weight")
    base[:k] = quant_tensor(prefix + "self_attn.k_proj.weight")
    base[:v] = quant_tensor(prefix + "self_attn.v_proj.weight")
    base[:out] = quant_tensor(prefix + "self_attn.o_proj.weight")
    base[:qn] = qn
    base[:kn] = kn
    base[:k_cache] = metal_buffer(device, MAX_POS * KV_DIM * 4)
    base[:v_cache] = metal_buffer(device, MAX_POS * KV_DIM * 4)
  layers.push(base)
  li = li + 1

# Inline MTP-1 head. Its decoder layer is full attention and shares the main
# embedding and LM head. The MTP KV cache advances on committed
# (look-ahead-token, target-hidden) pairs only, so a rejected target draft
# never needs to be removed from this cache.
mtp_layer = nil
mtp_enorm = nil
mtp_hnorm = nil
mtp_norm = nil
mtp_fc = nil
if mtp_enabled
  mtp_enorm = metal_buffer(device, HIDDEN * 4)
  mtp_hnorm = metal_buffer(device, HIDDEN * 4)
  mtp_norm = metal_buffer(device, HIDDEN * 4)
  mtp_in_norm = metal_buffer(device, HIDDEN * 4)
  mtp_post_norm = metal_buffer(device, HIDDEN * 4)
  mtp_qn = metal_buffer(device, HEAD_DIM * 4)
  mtp_kn = metal_buffer(device, HEAD_DIM * 4)
  load_shifted_norm(["mtp.pre_fc_norm_embedding.weight", HIDDEN, mtp_enorm])
  load_shifted_norm(["mtp.pre_fc_norm_hidden.weight", HIDDEN, mtp_hnorm])
  load_shifted_norm(["mtp.norm.weight", HIDDEN, mtp_norm])
  load_shifted_norm(["mtp.layers.0.input_layernorm.weight", HIDDEN, mtp_in_norm])
  load_shifted_norm(["mtp.layers.0.post_attention_layernorm.weight", HIDDEN, mtp_post_norm])
  load_shifted_norm(["mtp.layers.0.self_attn.q_norm.weight", HEAD_DIM, mtp_qn])
  load_shifted_norm(["mtp.layers.0.self_attn.k_norm.weight", HEAD_DIM, mtp_kn])
  mtp_fc = quant_tensor("mtp.fc.weight")
  mtp_layer = {
    kind: "full",
    in_norm: mtp_in_norm,
    post_norm: mtp_post_norm,
    q: quant_tensor("mtp.layers.0.self_attn.q_proj.weight"),
    k: quant_tensor("mtp.layers.0.self_attn.k_proj.weight"),
    v: quant_tensor("mtp.layers.0.self_attn.v_proj.weight"),
    out: quant_tensor("mtp.layers.0.self_attn.o_proj.weight"),
    qn: mtp_qn,
    kn: mtp_kn,
    gate: quant_tensor("mtp.layers.0.mlp.gate_proj.weight"),
    up: quant_tensor("mtp.layers.0.mlp.up_proj.weight"),
    down: quant_tensor("mtp.layers.0.mlp.down_proj.weight"),
    k_cache: metal_buffer(device, MAX_POS * KV_DIM * 4),
    v_cache: metal_buffer(device, MAX_POS * KV_DIM * 4)
  }

# Shared decode scratch.
x = metal_buffer(device, HIDDEN * 4)
xn = metal_buffer(device, HIDDEN * 4)
backbone_hidden = metal_buffer(device, HIDDEN * 4)
projection = metal_buffer(device, HIDDEN * 4)
ffn_out = metal_buffer(device, HIDDEN * 4)
gate_tmp = metal_buffer(device, FFN * 4)
up_tmp = metal_buffer(device, FFN * 4)
hidden_tmp = metal_buffer(device, FFN * 4)

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

# MTP fusion scratch.
mtp_embed_tmp = metal_buffer(device, HIDDEN * 4)
mtp_embed_norm_tmp = metal_buffer(device, HIDDEN * 4)
mtp_hidden_norm_tmp = metal_buffer(device, HIDDEN * 4)
mtp_fc_input_tmp = metal_buffer(device, HIDDEN * 2 * 4)
mtp_prefix_logits = metal_buffer(device, MTP_DRAFT_PREFIX * 4)
mtp_control_logits = metal_buffer(device, MTP_DRAFT_CONTROL_ROWS * 4)

# Two-token target-verification scratch. Pair projections use f32 throughout;
# packed weights remain mmap-backed and are decoded only in the pair qmv.
x_pair = metal_buffer(device, 2 * HIDDEN * 4)
xn_pair = metal_buffer(device, 2 * HIDDEN * 4)
gate_pair_tmp = metal_buffer(device, 2 * FFN * 4)
up_pair_tmp = metal_buffer(device, 2 * FFN * 4)
hidden_pair_tmp = metal_buffer(device, 2 * FFN * 4)

qkv_pair_tmp = metal_buffer(device, 2 * QKV_DIM * 4)
z_pair_tmp = metal_buffer(device, 2 * V_DIM * 4)
a_pair_tmp = metal_buffer(device, 2 * HV * 4)
b_pair_tmp = metal_buffer(device, 2 * HV * 4)
conv_pair_tmp = metal_buffer(device, 2 * QKV_DIM * 4)
mq_pair_tmp = metal_buffer(device, 2 * Q_DIM * 4)
mk_pair_tmp = metal_buffer(device, 2 * K_DIM * 4)
mv_pair_tmp = metal_buffer(device, 2 * V_DIM * 4)
g_pair_tmp = metal_buffer(device, 2 * HV * 4)
beta_pair_tmp = metal_buffer(device, 2 * HV * 4)
delta_pair_tmp = metal_buffer(device, 2 * V_DIM * 4)
mamba_norm_pair_tmp = metal_buffer(device, 2 * V_DIM * 4)

qfull_pair_tmp = metal_buffer(device, 2 * QFULL_DIM * 4)
queries_pair_tmp = metal_buffer(device, 2 * ATTN_DIM * 4)
attn_gate_pair_tmp = metal_buffer(device, 2 * ATTN_DIM * 4)
k_pair_tmp = metal_buffer(device, 2 * KV_DIM * 4)
v_pair_tmp = metal_buffer(device, 2 * KV_DIM * 4)
attn_pair_tmp = metal_buffer(device, 2 * ATTN_DIM * 4)
cos_pair_tmp = metal_buffer(device, 2 * ROT_HALF * 4)
sin_pair_tmp = metal_buffer(device, 2 * ROT_HALF * 4)

logits_pair = metal_buffer(device, 2 * N_VOCAB * 4)
argmax_pair_out = metal_buffer(device, 2 * 4)
token_pair_buf = metal_buffer(device, 2 * 4)

# Three-token target-verification scratch for the MTP-2 autotune arm.
x_triplet = metal_buffer(device, 3 * HIDDEN * 4)
xn_triplet = metal_buffer(device, 3 * HIDDEN * 4)
gate_triplet_tmp = metal_buffer(device, 3 * FFN * 4)
up_triplet_tmp = metal_buffer(device, 3 * FFN * 4)
hidden_triplet_tmp = metal_buffer(device, 3 * FFN * 4)
qkv_triplet_tmp = metal_buffer(device, 3 * QKV_DIM * 4)
z_triplet_tmp = metal_buffer(device, 3 * V_DIM * 4)
a_triplet_tmp = metal_buffer(device, 3 * HV * 4)
b_triplet_tmp = metal_buffer(device, 3 * HV * 4)
conv_triplet_tmp = metal_buffer(device, 3 * QKV_DIM * 4)
mq_triplet_tmp = metal_buffer(device, 3 * Q_DIM * 4)
mk_triplet_tmp = metal_buffer(device, 3 * K_DIM * 4)
mv_triplet_tmp = metal_buffer(device, 3 * V_DIM * 4)
g_triplet_tmp = metal_buffer(device, 3 * HV * 4)
beta_triplet_tmp = metal_buffer(device, 3 * HV * 4)
delta_triplet_tmp = metal_buffer(device, 3 * V_DIM * 4)
mamba_norm_triplet_tmp = metal_buffer(device, 3 * V_DIM * 4)
qfull_triplet_tmp = metal_buffer(device, 3 * QFULL_DIM * 4)
queries_triplet_tmp = metal_buffer(device, 3 * ATTN_DIM * 4)
attn_gate_triplet_tmp = metal_buffer(device, 3 * ATTN_DIM * 4)
k_triplet_tmp = metal_buffer(device, 3 * KV_DIM * 4)
v_triplet_tmp = metal_buffer(device, 3 * KV_DIM * 4)
attn_triplet_tmp = metal_buffer(device, 3 * ATTN_DIM * 4)
cos_triplet_tmp = metal_buffer(device, 3 * ROT_HALF * 4)
sin_triplet_tmp = metal_buffer(device, 3 * ROT_HALF * 4)
logits_triplet = metal_buffer(device, 3 * N_VOCAB * 4)
argmax_triplet_out = metal_buffer(device, 3 * 4)
token_triplet_buf = metal_buffer(device, 3 * 4)

# Four-token target-verification scratch (mtp3 / depth-3).
x_quad = metal_buffer(device, 4 * HIDDEN * 4)
xn_quad = metal_buffer(device, 4 * HIDDEN * 4)
gate_quad_tmp = metal_buffer(device, 4 * FFN * 4)
up_quad_tmp = metal_buffer(device, 4 * FFN * 4)
hidden_quad_tmp = metal_buffer(device, 4 * FFN * 4)
qkv_quad_tmp = metal_buffer(device, 4 * QKV_DIM * 4)
z_quad_tmp = metal_buffer(device, 4 * V_DIM * 4)
a_quad_tmp = metal_buffer(device, 4 * HV * 4)
b_quad_tmp = metal_buffer(device, 4 * HV * 4)
conv_quad_tmp = metal_buffer(device, 4 * QKV_DIM * 4)
mq_quad_tmp = metal_buffer(device, 4 * Q_DIM * 4)
mk_quad_tmp = metal_buffer(device, 4 * K_DIM * 4)
mv_quad_tmp = metal_buffer(device, 4 * V_DIM * 4)
g_quad_tmp = metal_buffer(device, 4 * HV * 4)
beta_quad_tmp = metal_buffer(device, 4 * HV * 4)
delta_quad_tmp = metal_buffer(device, 4 * V_DIM * 4)
mamba_norm_quad_tmp = metal_buffer(device, 4 * V_DIM * 4)
qfull_quad_tmp = metal_buffer(device, 4 * QFULL_DIM * 4)
queries_quad_tmp = metal_buffer(device, 4 * ATTN_DIM * 4)
attn_gate_quad_tmp = metal_buffer(device, 4 * ATTN_DIM * 4)
k_quad_tmp = metal_buffer(device, 4 * KV_DIM * 4)
v_quad_tmp = metal_buffer(device, 4 * KV_DIM * 4)
attn_quad_tmp = metal_buffer(device, 4 * ATTN_DIM * 4)
cos_quad_tmp = metal_buffer(device, 4 * ROT_HALF * 4)
sin_quad_tmp = metal_buffer(device, 4 * ROT_HALF * 4)
logits_quad = metal_buffer(device, 4 * N_VOCAB * 4)
argmax_quad_out = metal_buffer(device, 4 * 4)
token_quad_buf = metal_buffer(device, 4 * 4)

# Width-n block-verify scratch (multi). nil unless the multi path is selected.
x_multi = nil
if multi_verify
  x_multi = metal_buffer(device, MULTI_MAX * HIDDEN * 4)
  xn_multi = metal_buffer(device, MULTI_MAX * HIDDEN * 4)
  gate_multi_tmp = metal_buffer(device, MULTI_MAX * FFN * 4)
  up_multi_tmp = metal_buffer(device, MULTI_MAX * FFN * 4)
  xn_h16 = metal_buffer(device, MULTI_MAX * HIDDEN * 2)
  h_h16 = metal_buffer(device, MULTI_MAX * FFN * 2)
  down_na_tmp = metal_buffer(device, MULTI_MAX * HIDDEN * 4)
  # Staging for projections routed to the Neural Accelerators outside the FFN:
  # f16 activations (widest kdim is FFN) and, because the NA kernel has no
  # accumulate-into-C mode, a destination for the residual projections (whose
  # ndim is always HIDDEN) that a residual_add then folds into x_multi.
  na_in_h16 = metal_buffer(device, MULTI_MAX * FFN * 2)
  na_out_tmp = metal_buffer(device, MULTI_MAX * HIDDEN * 4)
  hidden_multi_tmp = metal_buffer(device, MULTI_MAX * FFN * 4)
  z_multi_tmp = metal_buffer(device, MULTI_MAX * V_DIM * 4)
  a_multi_tmp = metal_buffer(device, MULTI_MAX * HV * 4)
  b_multi_tmp = metal_buffer(device, MULTI_MAX * HV * 4)
  conv_multi_tmp = metal_buffer(device, MULTI_MAX * QKV_DIM * 4)
  delta_multi_tmp = metal_buffer(device, MULTI_MAX * V_DIM * 4)
  mamba_norm_multi_tmp = metal_buffer(device, MULTI_MAX * V_DIM * 4)
  qfull_multi_tmp = metal_buffer(device, MULTI_MAX * QFULL_DIM * 4)
  queries_multi_tmp = metal_buffer(device, MULTI_MAX * ATTN_DIM * 4)
  attn_gate_multi_tmp = metal_buffer(device, MULTI_MAX * ATTN_DIM * 4)
  k_multi_tmp = metal_buffer(device, MULTI_MAX * KV_DIM * 4)
  v_multi_tmp = metal_buffer(device, MULTI_MAX * KV_DIM * 4)
  attn_multi_tmp = metal_buffer(device, MULTI_MAX * ATTN_DIM * 4)
  cos_multi_tmp = metal_buffer(device, MULTI_MAX * ROT_HALF * 4)
  sin_multi_tmp = metal_buffer(device, MULTI_MAX * ROT_HALF * 4)
  logits_multi = metal_buffer(device, LOGITS_MULTI_MAX * N_VOCAB * 4)
  argmax_multi_out = metal_buffer(device, MULTI_MAX * 4)
  token_multi_buf = metal_buffer(device, MULTI_MAX * 4)
  # DFlash2 conditioning taps [MAX_POS, 5, HIDDEN] (65 MB), filled by the
  # verify's tap copies when a drafter wants them.
  ctx_hidden = metal_buffer(device, MAX_POS * 5 * HIDDEN * 4)
# Verify-row hidden staging source for the head-history appends.
x_verify4 = multi_verify ? x_multi : x_quad
x_verify3 = multi_verify ? x_multi : x_triplet

logits = metal_buffer(device, N_VOCAB * 4)
argmax_out = metal_buffer(device, 4)
rank_out = metal_buffer(device, 4)
n_vocab_buf = metal_buffer(device, 4)
metal_buffer_write_i32(n_vocab_buf, 0, N_VOCAB)
argmax_partial_values = metal_buffer(device, 8 * ARGMAX_CHUNKS * 4)
argmax_partial_indices = metal_buffer(device, 8 * ARGMAX_CHUNKS * 4)
# Tap table [MAX_POS, 5, HIDDEN] f32 (65 MB), filled device-side per position
# and read back once at the end. Only allocated for the tapdump diagnostic.
tap_buf = nil
if tapdump
  if mtp_enabled || devchain then raise "tapdump is a serial-path diagnostic: use mode concurrent without devchain"
  tap_buf = metal_buffer(device, MAX_POS * 5 * HIDDEN * 4)
# The dflash2 prefill captures the same taps straight into the drafter's
# context table.
tap_capture = tapdump || dflash2_enabled
if dflash2_enabled then tap_buf = ctx_hidden

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

-> build_rope_pair(pos_start)
  token = 0
  while token < 2
    i = 0
    while i < ROT_HALF
      theta = Math.exp(log_rope * (~0.0 - i * rope_power))
      angle = (pos_start + token) * theta
      metal_buffer_write_f32(cos_pair_tmp, token * ROT_HALF + i, Math.cos(angle))
      metal_buffer_write_f32(sin_pair_tmp, token * ROT_HALF + i, Math.sin(angle))
      i = i + 1
    token = token + 1

-> build_rope_triplet(pos_start)
  token = 0
  while token < 3
    i = 0
    while i < ROT_HALF
      theta = Math.exp(log_rope * (~0.0 - i * rope_power))
      angle = (pos_start + token) * theta
      metal_buffer_write_f32(cos_triplet_tmp, token * ROT_HALF + i, Math.cos(angle))
      metal_buffer_write_f32(sin_triplet_tmp, token * ROT_HALF + i, Math.sin(angle))
      i = i + 1
    token = token + 1

-> enqueue_scaled(spec)
  w = spec[0]
  input = spec[1]
  output = spec[2]
  kdim = spec[3]
  rows = spec[4]
  args = [w[0], w[1], input, output, kdim, w[2]]
  schedule = row_schedule
  if schedule == "auto"
    schedule = "8r"
    if kdim == FFN && rows == HIDDEN
      schedule = "16r"
    if rows == QKV_DIM || rows == V_DIM || rows == QFULL_DIM || (kdim == HIDDEN * 2 && rows == HIDDEN)
      schedule = "r2"
    if rows == KV_DIM || rows == N_VOCAB
      schedule = "4r"
  if schedule == "4r"
    metal_dispatch_groups(queue, scaled_4_pipe, args, rows / 4, 32)
  else
    if schedule == "16r"
      metal_dispatch_groups(queue, scaled_16_pipe, args, rows / 16, 128)
    else
      if schedule == "r2"
        metal_dispatch_groups(queue, r2_pipe, args, rows / 8, 64)
      else
        metal_dispatch_groups(queue, scaled_pipe, args, rows / 8, 64)

-> enqueue_scaled_pair(spec)
  w = spec[0]
  input = spec[1]
  output = spec[2]
  kdim = spec[3]
  rows = spec[4]
  metal_dispatch_groups(queue, scaled_pair_pipe,
    [w[0], w[1], input, output, kdim, rows, w[2]], (rows + 3) / 4, 64)

-> enqueue_residual_pair(spec)
  w = spec[0]
  input = spec[1]
  residual = spec[2]
  kdim = spec[3]
  rows = spec[4]
  metal_dispatch_groups(queue, scaled_pair_res_pipe,
    [w[0], w[1], input, residual, kdim, rows, w[2]], (rows + 3) / 4, 64)

-> enqueue_scaled_triplet(spec)
  w = spec[0]
  input = spec[1]
  output = spec[2]
  kdim = spec[3]
  rows = spec[4]
  # The wide/r1 split below was chosen from ISOLATED kernel timings. On this
  # kernel family isolated timings can inverse the in-situ answer: a 44-89 MB
  # weight tile re-read back to back is served by the system cache, while in
  # the real forward 18 GB streams past and nothing is resident. ARGV[6] =
  # "r1"|"wide" forces one variant everywhere so the split can be re-checked
  # at the full-model level.
  # "auto" is now the hoisted kernel everywhere. The wide/r1 split it used to
  # pick between was chosen from isolated timings and measured as a wash at the
  # full-model level (three variants, three reps, no separation); the real cost
  # was that BOTH re-read the activations once per output row. "wide" and
  # "rowsplit" remain selectable so the old split stays re-checkable.
  if triplet_variant == "b3r4" || (triplet_variant == "auto" && kdim == FFN)
    metal_dispatch_groups(queue, wide_b3_r4_pipe,
      [w[0], w[1], input, output, kdim, rows, w[2]], (rows + 7) / 8, 64)
    return
  if triplet_variant == "b3" || triplet_variant == "auto"
    metal_dispatch_groups(queue, wide_b3_pipe,
      [w[0], w[1], input, output, kdim, rows, w[2]], (rows + 3) / 4, 64)
    return
  if triplet_variant == "hoist" || triplet_variant == "auto"
    metal_dispatch_groups(queue, scaled_triplet_hoist_pipe,
      [w[0], w[1], input, output, kdim, rows, w[2]], (rows + 3) / 4, 64)
    return
  # "legacy" reproduces the pre-hoist default exactly (wide for FFN/vocab, r1
  # elsewhere) so the fix stays measurable; "wide"/"rowsplit" force one kernel
  # everywhere, as they always did.
  legacy_shape = kdim == FFN || rows == N_VOCAB
  use_wide = triplet_variant == "wide" || (triplet_variant == "legacy" && legacy_shape)
  if use_wide
    metal_dispatch_groups(queue, scaled_triplet_pipe,
      [w[0], w[1], input, output, kdim, rows, w[2]], (rows + 3) / 4, 64)
  else
    metal_dispatch_groups(queue, scaled_triplet_r1_pipe,
      [w[0], w[1], input, output, kdim, rows, w[2]], (rows + 1) / 2, 64)

-> enqueue_residual_triplet(spec)
  w = spec[0]
  input = spec[1]
  residual = spec[2]
  kdim = spec[3]
  rows = spec[4]
  if triplet_variant == "b3r4" || (triplet_variant == "auto" && kdim == FFN)
    metal_dispatch_groups(queue, wide_b3_r4_res_pipe,
      [w[0], w[1], input, residual, kdim, rows, w[2]], (rows + 7) / 8, 64)
    return
  if triplet_variant == "b3" || triplet_variant == "auto"
    metal_dispatch_groups(queue, wide_b3_res_pipe,
      [w[0], w[1], input, residual, kdim, rows, w[2]], (rows + 3) / 4, 64)
    return
  if triplet_variant == "hoist" || triplet_variant == "auto"
    metal_dispatch_groups(queue, scaled_triplet_res_hoist_pipe,
      [w[0], w[1], input, residual, kdim, rows, w[2]], (rows + 3) / 4, 64)
    return
  use_wide_res = triplet_variant == "wide" || (triplet_variant == "legacy" && kdim == FFN)
  if use_wide_res
    metal_dispatch_groups(queue, scaled_triplet_res_pipe,
      [w[0], w[1], input, residual, kdim, rows, w[2]], (rows + 3) / 4, 64)
  else
    metal_dispatch_groups(queue, scaled_triplet_res_r1_pipe,
      [w[0], w[1], input, residual, kdim, rows, w[2]], (rows + 1) / 2, 64)

-> enqueue_residual(spec)
  w = spec[0]
  input = spec[1]
  residual = spec[2]
  kdim = spec[3]
  rows = spec[4]
  if optimized
    metal_dispatch_groups(queue, scaled_res_pipe, [w[0], w[1], input, residual, kdim, w[2]], rows / 8, 64)
  else
    enqueue_scaled([w, input, projection, kdim, rows])
    metal_dispatch_n(queue, add_pipe, [residual, projection, rows], rows)

-> dependency_barrier
  if concurrent then metal_batch_barrier(queue)

# Barrier on only the buffers that actually carry the RAW dependency.
-> dep_barrier_on(bufs)
  if concurrent
    if scoped_barriers
      metal_batch_barrier_resources(queue, bufs)
    else
      metal_batch_barrier(queue)

-> enqueue_rms(spec)
  if legacy_reductions
    if spec[3] == 1
      metal_dispatch_groups(queue, rms_pipe,
        [spec[0], spec[1], spec[2], HIDDEN, ~1.0 / HIDDEN, EPS], 1, 256)
    elsif spec[3] == 2
      metal_dispatch_groups(queue, rms_pair_pipe,
        [spec[0], spec[1], spec[2], ~1.0 / HIDDEN, EPS], 2, 32)
    else
      metal_dispatch_groups(queue, rms_triplet_pipe,
        [spec[0], spec[1], spec[2], ~1.0 / HIDDEN, EPS], 3, 32)
  else
    metal_dispatch_groups(queue, rms_batch_pipe,
      [spec[0], spec[1], spec[2], HIDDEN, spec[3], ~1.0 / HIDDEN, EPS],
      spec[3], 512)

# Two-stage exact vocabulary reduction. The previous one-simdgroup argmax
# scanned all 248K logits twice and cost ~1.7 ms; this uses 1024-logit tiles
# and a small final reduction for all target widths.
-> enqueue_argmax(spec)
  input_logits = spec[0]
  output_index = spec[1]
  batch = spec[2]
  if legacy_reductions
    if batch == 1
      metal_dispatch_groups(queue, argmax_pipe,
        [input_logits, output_index, n_vocab_buf], 1, 32)
    elsif batch == 2
      metal_dispatch_groups(queue, argmax_pair_pipe,
        [input_logits, output_index], 2, 32)
    else
      metal_dispatch_groups(queue, argmax_triplet_pipe,
        [input_logits, output_index], 3, 32)
  else
    metal_dispatch_groups(queue, argmax_stage1_pipe,
      [input_logits, argmax_partial_values, argmax_partial_indices,
       N_VOCAB, ARGMAX_CHUNKS, batch], batch * ARGMAX_CHUNKS, 256)
    dependency_barrier()
    metal_dispatch_groups(queue, argmax_stage2_pipe,
      [argmax_partial_values, argmax_partial_indices, output_index,
       ARGMAX_CHUNKS, batch], batch, 256)

-> enqueue_mamba(lyr)
  cs_in = lyr[:cs_a]
  cs_out = lyr[:cs_b]
  ss_in = lyr[:ss_a]
  ss_out = lyr[:ss_b]
  if lyr[:ping] == 1
    cs_in = lyr[:cs_b]
    cs_out = lyr[:cs_a]
    ss_in = lyr[:ss_b]
    ss_out = lyr[:ss_a]
  enqueue_rms([x, lyr[:in_norm], xn, 1])
  dependency_barrier()
  enqueue_scaled([lyr[:qkv], xn, qkv_tmp, HIDDEN, QKV_DIM])
  enqueue_scaled([lyr[:z], xn, z_tmp, HIDDEN, V_DIM])
  metal_dispatch_groups(queue, bf16_matvec_pipe, [lyr[:a], xn, a_tmp, HIDDEN], HV, 32)
  metal_dispatch_groups(queue, bf16_matvec_pipe, [lyr[:b], xn, b_tmp, HIDDEN], HV, 32)
  dependency_barrier()
  metal_dispatch_n(queue, conv_pipe, [lyr[:conv], cs_in, qkv_tmp, conv_tmp, cs_out, QKV_DIM, QKV_DIM], QKV_DIM)
  dependency_barrier()
  metal_dispatch_n(queue, copy_pipe, [conv_tmp, mq_tmp, 0, Q_DIM], Q_DIM)
  metal_dispatch_n(queue, copy_pipe, [conv_tmp, mk_tmp, Q_DIM, K_DIM], K_DIM)
  metal_dispatch_n(queue, copy_pipe, [conv_tmp, mv_tmp, Q_DIM + K_DIM, V_DIM], V_DIM)
  dependency_barrier()
  metal_dispatch_groups(queue, phn_pipe, [mq_tmp, q_norm_scale, DK, ~1.0 / DK, EPS], HK, 32)
  metal_dispatch_groups(queue, phn_pipe, [mk_tmp, k_norm_scale, DK, ~1.0 / DK, EPS], HK, 32)
  metal_dispatch_n(queue, g_pipe, [a_tmp, lyr[:alog], lyr[:dtb], g_tmp, HV, HV], HV)
  metal_dispatch_n(queue, sigmoid_pipe, [b_tmp, beta_tmp, HV], HV)
  dependency_barrier()
  metal_dispatch_3d(queue, delta_pipe, [mq_tmp, mk_tmp, mv_tmp, g_tmp, beta_tmp, ss_in, delta_tmp, ss_out, HK, HV, DK, DV], 1, DV / 4, HV, 32, 4, 1)
  dependency_barrier()
  metal_dispatch_groups(queue, rng_pipe, [delta_tmp, z_tmp, lyr[:linear_norm], mamba_norm_tmp, DV, EPS], HV, 32)
  dependency_barrier()
  enqueue_residual([lyr[:out], mamba_norm_tmp, x, V_DIM, HIDDEN])
  dependency_barrier()
  lyr[:ping] = 1 - lyr[:ping]

-> enqueue_full(lyr, pos)
  enqueue_rms([x, lyr[:in_norm], xn, 1])
  dependency_barrier()
  enqueue_scaled([lyr[:q], xn, qfull_tmp, HIDDEN, QFULL_DIM])
  enqueue_scaled([lyr[:k], xn, k_tmp, HIDDEN, KV_DIM])
  enqueue_scaled([lyr[:v], xn, v_tmp, HIDDEN, KV_DIM])
  dependency_barrier()
  metal_dispatch_n(queue, split_pipe, [qfull_tmp, queries_tmp, attn_gate_tmp, N_HEADS, HEAD_DIM], ATTN_DIM)
  dependency_barrier()
  metal_dispatch_groups(queue, phn_pipe, [queries_tmp, lyr[:qn], HEAD_DIM, ~1.0 / HEAD_DIM, EPS], N_HEADS, 32)
  metal_dispatch_groups(queue, phn_pipe, [k_tmp, lyr[:kn], HEAD_DIM, ~1.0 / HEAD_DIM, EPS], N_KV_HEADS, 32)
  dependency_barrier()
  if pos > 0
    metal_dispatch_n(queue, rope_pipe, [queries_tmp, cos_tmp, sin_tmp, HEAD_DIM, ROT_HALF, N_HEADS], N_HEADS * ROT_HALF)
    metal_dispatch_n(queue, rope_pipe, [k_tmp, cos_tmp, sin_tmp, HEAD_DIM, ROT_HALF, N_KV_HEADS], N_KV_HEADS * ROT_HALF)
  dependency_barrier()
  metal_dispatch_n(queue, kv_write_pipe, [k_tmp, lyr[:k_cache], pos, KV_DIM], KV_DIM)
  metal_dispatch_n(queue, kv_write_pipe, [v_tmp, lyr[:v_cache], pos, KV_DIM], KV_DIM)
  dependency_barrier()
  metal_dispatch_groups(queue, sdpa_pipe, [queries_tmp, lyr[:k_cache], lyr[:v_cache], attn_tmp, GQA, pos + 1, HEAD_DIM, KV_DIM, ATTN_SCALE], N_HEADS, 256)
  dependency_barrier()
  metal_dispatch_n(queue, gate_pipe, [attn_tmp, attn_gate_tmp, ATTN_DIM], ATTN_DIM)
  dependency_barrier()
  enqueue_residual([lyr[:out], attn_tmp, x, ATTN_DIM, HIDDEN])
  dependency_barrier()

-> enqueue_ffn(lyr)
  enqueue_rms([x, lyr[:post_norm], xn, 1])
  dependency_barrier()
  if optimized
    metal_dispatch_groups(queue, scaled_gu_pipe, [lyr[:gate][0], lyr[:gate][1], lyr[:up][0], lyr[:up][1], xn, gate_tmp, up_tmp, HIDDEN, FFN / 8, lyr[:gate][2], lyr[:up][2]], (FFN / 8) * 2, 64)
  else
    enqueue_scaled([lyr[:gate], xn, gate_tmp, HIDDEN, FFN])
    enqueue_scaled([lyr[:up], xn, up_tmp, HIDDEN, FFN])
  dependency_barrier()
  metal_dispatch_n(queue, silu_pipe, [gate_tmp, up_tmp, hidden_tmp, FFN], FFN)
  dependency_barrier()
  if optimized
    metal_dispatch_groups(queue, scaled_res_pipe, [lyr[:down][0], lyr[:down][1], hidden_tmp, x, FFN, lyr[:down][2]], HIDDEN / 8, 64)
  else
    enqueue_scaled([lyr[:down], hidden_tmp, ffn_out, FFN, HIDDEN])
    metal_dispatch_n(queue, add_pipe, [x, ffn_out, HIDDEN], HIDDEN)
  dependency_barrier()

-> enqueue_mamba_pair(lyr)
  cs_in = lyr[:cs_a]
  cs_out = lyr[:cs_b]
  ss_in = lyr[:ss_a]
  ss_out = lyr[:ss_b]
  if lyr[:ping] == 1
    cs_in = lyr[:cs_b]
    cs_out = lyr[:cs_a]
    ss_in = lyr[:ss_b]
    ss_out = lyr[:ss_a]
  enqueue_rms([x_pair, lyr[:in_norm], xn_pair, 2])
  dependency_barrier()
  enqueue_scaled_pair([lyr[:qkv], xn_pair, qkv_pair_tmp, HIDDEN, QKV_DIM])
  enqueue_scaled_pair([lyr[:z], xn_pair, z_pair_tmp, HIDDEN, V_DIM])
  metal_dispatch_groups(queue, pair_bf16_pipe,
    [lyr[:a], xn_pair, a_pair_tmp, HIDDEN, HV], HV, 32)
  metal_dispatch_groups(queue, pair_bf16_pipe,
    [lyr[:b], xn_pair, b_pair_tmp, HIDDEN, HV], HV, 32)
  dependency_barrier()
  metal_dispatch_n(queue, conv_pair_pipe,
    [lyr[:conv], cs_in, qkv_pair_tmp, conv_pair_tmp, lyr[:cs_mid], cs_out, QKV_DIM], QKV_DIM)
  dependency_barrier()
  metal_dispatch_n(queue, copy_pair_slice_pipe,
    [conv_pair_tmp, mq_pair_tmp, QKV_DIM, Q_DIM, 0, Q_DIM], 2 * Q_DIM)
  metal_dispatch_n(queue, copy_pair_slice_pipe,
    [conv_pair_tmp, mk_pair_tmp, QKV_DIM, K_DIM, Q_DIM, K_DIM], 2 * K_DIM)
  metal_dispatch_n(queue, copy_pair_slice_pipe,
    [conv_pair_tmp, mv_pair_tmp, QKV_DIM, V_DIM, Q_DIM + K_DIM, V_DIM], 2 * V_DIM)
  dependency_barrier()
  metal_dispatch_groups(queue, phn_pipe,
    [mq_pair_tmp, q_norm_scale, DK, ~1.0 / DK, EPS], 2 * HK, 32)
  metal_dispatch_groups(queue, phn_pipe,
    [mk_pair_tmp, k_norm_scale, DK, ~1.0 / DK, EPS], 2 * HK, 32)
  metal_dispatch_n(queue, g_pipe,
    [a_pair_tmp, lyr[:alog], lyr[:dtb], g_pair_tmp, HV, 2 * HV], 2 * HV)
  metal_dispatch_n(queue, sigmoid_pipe, [b_pair_tmp, beta_pair_tmp, 2 * HV], 2 * HV)
  dependency_barrier()
  metal_dispatch_3d(queue, delta_pair_pipe,
    [mq_pair_tmp, mk_pair_tmp, mv_pair_tmp, g_pair_tmp, beta_pair_tmp,
     ss_in, delta_pair_tmp, lyr[:ss_mid], ss_out, HK, HV, DK, DV],
    1, DV / 4, HV, 32, 4, 1)
  dependency_barrier()
  metal_dispatch_groups(queue, rng_pipe,
    [delta_pair_tmp, z_pair_tmp, lyr[:linear_norm], mamba_norm_pair_tmp, DV, EPS],
    2 * HV, 32)
  dependency_barrier()
  enqueue_residual_pair([lyr[:out], mamba_norm_pair_tmp, x_pair, V_DIM, HIDDEN])
  dependency_barrier()
  lyr[:ping] = 1 - lyr[:ping]

-> enqueue_full_pair(spec)
  lyr = spec[0]
  pos_start = spec[1]
  enqueue_rms([x_pair, lyr[:in_norm], xn_pair, 2])
  dependency_barrier()
  enqueue_scaled_pair([lyr[:q], xn_pair, qfull_pair_tmp, HIDDEN, QFULL_DIM])
  enqueue_scaled_pair([lyr[:k], xn_pair, k_pair_tmp, HIDDEN, KV_DIM])
  enqueue_scaled_pair([lyr[:v], xn_pair, v_pair_tmp, HIDDEN, KV_DIM])
  dependency_barrier()
  metal_dispatch_n(queue, split_pair_pipe,
    [qfull_pair_tmp, queries_pair_tmp, attn_gate_pair_tmp, N_HEADS, HEAD_DIM],
    2 * ATTN_DIM)
  dependency_barrier()
  metal_dispatch_groups(queue, phn_rope_pair_pipe,
    [queries_pair_tmp, lyr[:qn], cos_pair_tmp, sin_pair_tmp,
     HEAD_DIM, ROT_HALF, N_HEADS, ~1.0 / HEAD_DIM, EPS], 2 * N_HEADS, 32)
  metal_dispatch_groups(queue, phn_rope_pair_pipe,
    [k_pair_tmp, lyr[:kn], cos_pair_tmp, sin_pair_tmp,
     HEAD_DIM, ROT_HALF, N_KV_HEADS, ~1.0 / HEAD_DIM, EPS], 2 * N_KV_HEADS, 32)
  dependency_barrier()
  metal_dispatch_n(queue, kv_write_pair_pipe,
    [k_pair_tmp, v_pair_tmp, lyr[:k_cache], lyr[:v_cache], pos_start, KV_DIM],
    2 * KV_DIM)
  dependency_barrier()
  metal_dispatch_groups(queue, sdpa_pair_pipe,
    [queries_pair_tmp, lyr[:k_cache], lyr[:v_cache], attn_pair_tmp,
     GQA, pos_start, N_HEADS, KV_DIM, ATTN_SCALE], 2 * N_HEADS, 256)
  dependency_barrier()
  metal_dispatch_n(queue, gate_pipe,
    [attn_pair_tmp, attn_gate_pair_tmp, 2 * ATTN_DIM], 2 * ATTN_DIM)
  dependency_barrier()
  enqueue_residual_pair([lyr[:out], attn_pair_tmp, x_pair, ATTN_DIM, HIDDEN])
  dependency_barrier()

-> enqueue_ffn_pair(lyr)
  enqueue_rms([x_pair, lyr[:post_norm], xn_pair, 2])
  dependency_barrier()
  enqueue_scaled_pair([lyr[:gate], xn_pair, gate_pair_tmp, HIDDEN, FFN])
  enqueue_scaled_pair([lyr[:up], xn_pair, up_pair_tmp, HIDDEN, FFN])
  dependency_barrier()
  metal_dispatch_n(queue, silu_pipe,
    [gate_pair_tmp, up_pair_tmp, hidden_pair_tmp, 2 * FFN], 2 * FFN)
  dependency_barrier()
  enqueue_residual_pair([lyr[:down], hidden_pair_tmp, x_pair, FFN, HIDDEN])
  dependency_barrier()

-> enqueue_mamba_triplet(lyr)
  cs_in = lyr[:cs_a]
  cs_out = lyr[:cs_b]
  ss_in = lyr[:ss_a]
  ss_out = lyr[:ss_b]
  if lyr[:ping] == 1
    cs_in = lyr[:cs_b]
    cs_out = lyr[:cs_a]
    ss_in = lyr[:ss_b]
    ss_out = lyr[:ss_a]
  enqueue_rms([x_triplet, lyr[:in_norm], xn_triplet, 3])
  dependency_barrier()
  enqueue_scaled_triplet([lyr[:qkv], xn_triplet, qkv_triplet_tmp, HIDDEN, QKV_DIM])
  enqueue_scaled_triplet([lyr[:z], xn_triplet, z_triplet_tmp, HIDDEN, V_DIM])
  metal_dispatch_groups(queue, triplet_bf16_pipe,
    [lyr[:a], xn_triplet, a_triplet_tmp, HIDDEN, HV], HV, 32)
  metal_dispatch_groups(queue, triplet_bf16_pipe,
    [lyr[:b], xn_triplet, b_triplet_tmp, HIDDEN, HV], HV, 32)
  dependency_barrier()
  metal_dispatch_n(queue, conv_triplet_pipe,
    [lyr[:conv], cs_in, qkv_triplet_tmp, conv_triplet_tmp,
     lyr[:cs_mid], lyr[:cs_mid2], cs_out, QKV_DIM], QKV_DIM)
  dependency_barrier()
  metal_dispatch_n(queue, copy_triplet_slice_pipe,
    [conv_triplet_tmp, mq_triplet_tmp, QKV_DIM, Q_DIM, 0, Q_DIM], 3 * Q_DIM)
  metal_dispatch_n(queue, copy_triplet_slice_pipe,
    [conv_triplet_tmp, mk_triplet_tmp, QKV_DIM, K_DIM, Q_DIM, K_DIM], 3 * K_DIM)
  metal_dispatch_n(queue, copy_triplet_slice_pipe,
    [conv_triplet_tmp, mv_triplet_tmp, QKV_DIM, V_DIM, Q_DIM + K_DIM, V_DIM], 3 * V_DIM)
  dependency_barrier()
  metal_dispatch_groups(queue, phn_pipe,
    [mq_triplet_tmp, q_norm_scale, DK, ~1.0 / DK, EPS], 3 * HK, 32)
  metal_dispatch_groups(queue, phn_pipe,
    [mk_triplet_tmp, k_norm_scale, DK, ~1.0 / DK, EPS], 3 * HK, 32)
  metal_dispatch_n(queue, g_pipe,
    [a_triplet_tmp, lyr[:alog], lyr[:dtb], g_triplet_tmp, HV, 3 * HV], 3 * HV)
  metal_dispatch_n(queue, sigmoid_pipe,
    [b_triplet_tmp, beta_triplet_tmp, 3 * HV], 3 * HV)
  dependency_barrier()
  metal_dispatch_3d(queue, delta_triplet_pipe,
    [mq_triplet_tmp, mk_triplet_tmp, mv_triplet_tmp, g_triplet_tmp,
     beta_triplet_tmp, ss_in, delta_triplet_tmp, lyr[:ss_mid],
     lyr[:ss_mid2], ss_out, HK, HV, DK, DV],
    1, DV / 4, HV, 32, 4, 1)
  dependency_barrier()
  metal_dispatch_groups(queue, rng_pipe,
    [delta_triplet_tmp, z_triplet_tmp, lyr[:linear_norm],
     mamba_norm_triplet_tmp, DV, EPS], 3 * HV, 32)
  dependency_barrier()
  enqueue_residual_triplet(
    [lyr[:out], mamba_norm_triplet_tmp, x_triplet, V_DIM, HIDDEN])
  dependency_barrier()
  lyr[:ping] = 1 - lyr[:ping]

-> enqueue_full_triplet(spec)
  lyr = spec[0]
  pos_start = spec[1]
  enqueue_rms([x_triplet, lyr[:in_norm], xn_triplet, 3])
  dependency_barrier()
  enqueue_scaled_triplet([lyr[:q], xn_triplet, qfull_triplet_tmp, HIDDEN, QFULL_DIM])
  enqueue_scaled_triplet([lyr[:k], xn_triplet, k_triplet_tmp, HIDDEN, KV_DIM])
  enqueue_scaled_triplet([lyr[:v], xn_triplet, v_triplet_tmp, HIDDEN, KV_DIM])
  dependency_barrier()
  metal_dispatch_n(queue, split_triplet_pipe,
    [qfull_triplet_tmp, queries_triplet_tmp, attn_gate_triplet_tmp,
     N_HEADS, HEAD_DIM], 3 * ATTN_DIM)
  dependency_barrier()
  metal_dispatch_groups(queue, phn_rope_triplet_pipe,
    [queries_triplet_tmp, lyr[:qn], cos_triplet_tmp, sin_triplet_tmp,
     HEAD_DIM, ROT_HALF, N_HEADS, ~1.0 / HEAD_DIM, EPS], 3 * N_HEADS, 32)
  metal_dispatch_groups(queue, phn_rope_triplet_pipe,
    [k_triplet_tmp, lyr[:kn], cos_triplet_tmp, sin_triplet_tmp,
     HEAD_DIM, ROT_HALF, N_KV_HEADS, ~1.0 / HEAD_DIM, EPS], 3 * N_KV_HEADS, 32)
  dependency_barrier()
  metal_dispatch_n(queue, kv_write_triplet_pipe,
    [k_triplet_tmp, v_triplet_tmp, lyr[:k_cache], lyr[:v_cache],
     pos_start, KV_DIM], 3 * KV_DIM)
  dependency_barrier()
  metal_dispatch_groups(queue, sdpa_triplet_pipe,
    [queries_triplet_tmp, lyr[:k_cache], lyr[:v_cache], attn_triplet_tmp,
     GQA, pos_start, N_HEADS, KV_DIM, ATTN_SCALE], 3 * N_HEADS, 256)
  dependency_barrier()
  metal_dispatch_n(queue, gate_pipe,
    [attn_triplet_tmp, attn_gate_triplet_tmp, 3 * ATTN_DIM], 3 * ATTN_DIM)
  dependency_barrier()
  enqueue_residual_triplet(
    [lyr[:out], attn_triplet_tmp, x_triplet, ATTN_DIM, HIDDEN])
  dependency_barrier()

-> enqueue_ffn_triplet(lyr)
  enqueue_rms([x_triplet, lyr[:post_norm], xn_triplet, 3])
  dep_barrier_on([xn_triplet])
  enqueue_scaled_triplet([lyr[:gate], xn_triplet, gate_triplet_tmp, HIDDEN, FFN])
  enqueue_scaled_triplet([lyr[:up], xn_triplet, up_triplet_tmp, HIDDEN, FFN])
  dep_barrier_on([gate_triplet_tmp, up_triplet_tmp])
  metal_dispatch_n(queue, silu_pipe,
    [gate_triplet_tmp, up_triplet_tmp, hidden_triplet_tmp, 3 * FFN], 3 * FFN)
  dep_barrier_on([hidden_triplet_tmp])
  enqueue_residual_triplet(
    [lyr[:down], hidden_triplet_tmp, x_triplet, FFN, HIDDEN])
  dep_barrier_on([x_triplet])

# A committed MTP-history row only needs to append the attention K/V derived
# from the fused embedding/target-hidden input. Q, attention output, the MLP,
# final norm, and vocabulary projection are dead for this row.
-> enqueue_mtp_history(lyr, pos)
  enqueue_rms([x, lyr[:in_norm], xn, 1])
  dependency_barrier()
  enqueue_scaled([lyr[:k], xn, k_tmp, HIDDEN, KV_DIM])
  enqueue_scaled([lyr[:v], xn, v_tmp, HIDDEN, KV_DIM])
  dependency_barrier()
  metal_dispatch_groups(queue, phn_pipe,
    [k_tmp, lyr[:kn], HEAD_DIM, ~1.0 / HEAD_DIM, EPS], N_KV_HEADS, 32)
  dependency_barrier()
  if pos > 0
    metal_dispatch_n(queue, rope_pipe,
      [k_tmp, cos_tmp, sin_tmp, HEAD_DIM, ROT_HALF, N_KV_HEADS],
      N_KV_HEADS * ROT_HALF)
  dependency_barrier()
  metal_dispatch_n(queue, kv_write_pipe,
    [k_tmp, lyr[:k_cache], pos, KV_DIM], KV_DIM)
  metal_dispatch_n(queue, kv_write_pipe,
    [v_tmp, lyr[:v_cache], pos, KV_DIM], KV_DIM)
  dependency_barrier()

-> mtp_step(spec)
  profile_t0 = profile_components ? ccall("__w_clock_ms") : ~0.0
  token_id = spec[0]
  hidden_in = spec[1]
  pos = spec[2]
  want_draft = legacy_mtp || full_history_mtp || spec.size() < 4 || spec[3]
  # Optional [src, row]: stage the verify's hidden row into backbone_hidden
  # inside THIS command buffer. It used to be its own begin/commit pair, which
  # for a HIDDEN-sized copy is almost entirely commit overhead (0.17 ms for
  # ~20 us of work), and there are two or three of them per round.
  stage_hidden = spec.size() > 4 && spec[4]
  # Optional [dst_buf, dst_idx]: instead of committing and reading the draft
  # argmax back to the host, copy it device-side into dst_buf[dst_idx] and
  # commit async, returning the command-buffer handle. The caller stacks it
  # straight into the next verify and reads the id only after that verify.
  mtp_defer = spec.size() > 5 ? spec[5] : nil
  # Optional [tok_buf, idx]: read the input token id from a device buffer
  # slot instead of the host scalar spec[0]. Lets draft k+1 consume draft
  # k's deferred argmax with no host round-trip (depth-3 device chain).
  mtp_dev_in = spec.size() > 6 ? spec[6] : nil
  if pos > 0 then build_rope(pos)
  metal_batch_begin_concurrent(queue)
  if stage_hidden
    metal_dispatch_n(queue, copy_pair_row_pipe,
      [spec[4][0], backbone_hidden, spec[4][1], HIDDEN], HIDDEN)
  if mtp_dev_in
    metal_dispatch_n(queue, bf16_embed_buf_pipe,
      [embed_w, mtp_embed_tmp, mtp_dev_in[0], mtp_dev_in[1], HIDDEN], HIDDEN)
  else
    metal_dispatch_n(queue, bf16_embed_pipe,
      [embed_w, mtp_embed_tmp, token_id, HIDDEN], HIDDEN)
  dependency_barrier()
  enqueue_rms([mtp_embed_tmp, mtp_enorm, mtp_embed_norm_tmp, 1])
  enqueue_rms([hidden_in, mtp_hnorm, mtp_hidden_norm_tmp, 1])
  dependency_barrier()
  metal_dispatch_n(queue, concat_pipe,
    [mtp_embed_norm_tmp, mtp_hidden_norm_tmp, mtp_fc_input_tmp, HIDDEN], HIDDEN)
  dependency_barrier()
  enqueue_scaled([mtp_fc, mtp_fc_input_tmp, x, HIDDEN * 2, HIDDEN])
  dependency_barrier()
  if want_draft
    enqueue_full(mtp_layer, pos)
    enqueue_ffn(mtp_layer)
    enqueue_rms([x, mtp_norm, xn, 1])
    dependency_barrier()
    if full_draft_vocab
      enqueue_scaled([lm_head, xn, logits, HIDDEN, N_VOCAB])
      dependency_barrier()
      enqueue_argmax([logits, argmax_out, 1])
    else
      enqueue_scaled([mtp_draft_prefix_head, xn, mtp_prefix_logits,
        HIDDEN, MTP_DRAFT_PREFIX])
      enqueue_scaled([mtp_draft_control_head, xn, mtp_control_logits,
        HIDDEN, MTP_DRAFT_CONTROL_ROWS])
      dependency_barrier()
      if fast_draft_select
        metal_dispatch_groups(queue, mtp_sel1_pipe,
          [mtp_prefix_logits, mtp_control_logits, mtp_sel_vals, mtp_sel_ids,
           MTP_DRAFT_PREFIX, MTP_DRAFT_CONTROL_COUNT, MTP_DRAFT_CONTROL_START],
          MTP_SEL_TILES, 256)
        dependency_barrier()
        metal_dispatch_groups(queue, mtp_sel2_pipe,
          [mtp_sel_vals, mtp_sel_ids, argmax_out, MTP_SEL_TILES], 1, 256)
      else
        metal_dispatch_groups(queue, mtp_select_pipe,
          [mtp_prefix_logits, mtp_control_logits, argmax_out,
           MTP_DRAFT_PREFIX, MTP_DRAFT_CONTROL_COUNT, MTP_DRAFT_CONTROL_START],
          1, 32)
  else
    enqueue_mtp_history(mtp_layer, pos)
  if mtp_defer
    dependency_barrier()
    metal_dispatch_n(queue, copy_i32_at_pipe,
      [argmax_out, mtp_defer[0], 0, mtp_defer[1]], 1)
    metal_batch_commit_async(queue)
  elsif devchain && !want_draft && profile_stats[0] == 0
    # Decode-phase history append (KV only, no host value): commit async,
    # drained by the round's next sync; handle released at round end.
    hist_cbs[hist_cb_n[0]] = metal_batch_commit_async(queue)
    hist_cb_n[0] = hist_cb_n[0] + 1
    -1
  else
    metal_batch_commit(queue)
    result = want_draft ? metal_buffer_read_i32(argmax_out, 0) : -1
    if profile_components
      profile_dt = ccall("__w_clock_ms") - profile_t0
      if want_draft
        profile_stats[7] = profile_stats[7] + profile_dt
        profile_stats[8] = profile_stats[8] + 1
      else
        profile_stats[9] = profile_stats[9] + profile_dt
        profile_stats[10] = profile_stats[10] + 1
    result

# Diagnostic: where did the target's token sit in the head's draft ranking?
# Reads the head logits left behind by the most recent mtp_step, so it must be
# called before any further mtp_step overwrites them.
-> draft_target_rank(target_id)
  metal_batch_begin_concurrent(queue)
  metal_dispatch_groups(queue, mtp_rank_pipe,
    [mtp_prefix_logits, mtp_control_logits, rank_out,
     MTP_DRAFT_PREFIX, MTP_DRAFT_CONTROL_COUNT, MTP_DRAFT_CONTROL_START,
     target_id],
    1, 32)
  metal_batch_commit(queue)
  metal_buffer_read_i32(rank_out, 0)

-> forward_pair(spec)
  profile_t0 = profile_components ? ccall("__w_clock_ms") : ~0.0
  token0 = spec[0]
  token1 = spec[1]
  pos_start = spec[2]
  build_rope_pair(pos_start)
  metal_buffer_write_i32(token_pair_buf, 0, token0)
  metal_buffer_write_i32(token_pair_buf, 1, token1)
  metal_batch_begin_concurrent(queue)
  metal_dispatch_n(queue, pair_embed_pipe,
    [embed_w, x_pair, token_pair_buf, HIDDEN], 2 * HIDDEN)
  dependency_barrier()
  li = 0
  while li < N_LAYERS
    lyr = layers[li]
    if lyr[:kind] == "mamba"
      enqueue_mamba_pair(lyr)
    else
      enqueue_full_pair([lyr, pos_start])
    enqueue_ffn_pair(lyr)
    li = li + 1
  enqueue_rms([x_pair, final_norm, xn_pair, 2])
  dependency_barrier()
  enqueue_scaled_pair([lm_head, xn_pair, logits_pair, HIDDEN, N_VOCAB])
  dependency_barrier()
  enqueue_argmax([logits_pair, argmax_pair_out, 2])
  metal_batch_commit(queue)
  result = [metal_buffer_read_i32(argmax_pair_out, 0), metal_buffer_read_i32(argmax_pair_out, 1)]
  if profile_components
    profile_stats[5] = profile_stats[5] + ccall("__w_clock_ms") - profile_t0
    profile_stats[6] = profile_stats[6] + 1
  result

-> forward_triplet(spec)
  profile_t0 = profile_components ? ccall("__w_clock_ms") : ~0.0
  token0 = spec[0]
  token1 = spec[1]
  token2 = spec[2]
  pos_start = spec[3]
  # spec[4] set => token slot 2 was already filled device-side by a deferred
  # draft (copy_i32_at); the host must not clobber it.
  dev_slot2 = spec.size() > 4 && spec[4]
  build_rope_triplet(pos_start)
  metal_buffer_write_i32(token_triplet_buf, 0, token0)
  metal_buffer_write_i32(token_triplet_buf, 1, token1)
  if !dev_slot2
    metal_buffer_write_i32(token_triplet_buf, 2, token2)
  metal_batch_begin_concurrent(queue)
  metal_dispatch_n(queue, triplet_embed_pipe,
    [embed_w, x_triplet, token_triplet_buf, HIDDEN], 3 * HIDDEN)
  dependency_barrier()
  li = 0
  while li < N_LAYERS
    lyr = layers[li]
    if lyr[:kind] == "mamba"
      enqueue_mamba_triplet(lyr)
    else
      enqueue_full_triplet([lyr, pos_start])
    enqueue_ffn_triplet(lyr)
    li = li + 1
  enqueue_rms([x_triplet, final_norm, xn_triplet, 3])
  dependency_barrier()
  enqueue_scaled_triplet([lm_head, xn_triplet, logits_triplet, HIDDEN, N_VOCAB])
  dependency_barrier()
  enqueue_argmax([logits_triplet, argmax_triplet_out, 3])
  metal_batch_commit(queue)
  result = [metal_buffer_read_i32(argmax_triplet_out, 0),
    metal_buffer_read_i32(argmax_triplet_out, 1),
    metal_buffer_read_i32(argmax_triplet_out, 2)]
  if profile_components
    profile_stats[5] = profile_stats[5] + ccall("__w_clock_ms") - profile_t0
    profile_stats[6] = profile_stats[6] + 1
  result

-> copy_hidden_pair_row(row)
  profile_t0 = profile_components ? ccall("__w_clock_ms") : ~0.0
  metal_batch_begin(queue)
  metal_dispatch_n(queue, copy_pair_row_pipe,
    [x_pair, backbone_hidden, row, HIDDEN], HIDDEN)
  metal_batch_commit(queue)
  if profile_components
    profile_stats[11] = profile_stats[11] + ccall("__w_clock_ms") - profile_t0
    profile_stats[12] = profile_stats[12] + 1

-> copy_hidden_triplet_row(row)
  profile_t0 = profile_components ? ccall("__w_clock_ms") : ~0.0
  metal_batch_begin(queue)
  metal_dispatch_n(queue, copy_pair_row_pipe,
    [x_triplet, backbone_hidden, row, HIDDEN], HIDDEN)
  metal_batch_commit(queue)
  if profile_components
    profile_stats[11] = profile_stats[11] + ccall("__w_clock_ms") - profile_t0
    profile_stats[12] = profile_stats[12] + 1

# ---- depth-3 (four-row verify) path, generated from the triplet path ----
-> build_rope_quad(pos_start)
  token = 0
  while token < 4
    i = 0
    while i < ROT_HALF
      theta = Math.exp(log_rope * (~0.0 - i * rope_power))
      angle = (pos_start + token) * theta
      metal_buffer_write_f32(cos_quad_tmp, token * ROT_HALF + i, Math.cos(angle))
      metal_buffer_write_f32(sin_quad_tmp, token * ROT_HALF + i, Math.sin(angle))
      i = i + 1
    token = token + 1

-> enqueue_scaled_quad(spec)
  w = spec[0]
  input = spec[1]
  output = spec[2]
  kdim = spec[3]
  rows = spec[4]
  metal_dispatch_groups(queue, wide_b4h_pipe,
    [w[0], w[1], input, output, kdim, rows, w[2]], (rows + 3) / 4, 64)

-> enqueue_residual_quad(spec)
  w = spec[0]
  input = spec[1]
  residual = spec[2]
  kdim = spec[3]
  rows = spec[4]
  metal_dispatch_groups(queue, wide_b4h_res_pipe,
    [w[0], w[1], input, residual, kdim, rows, w[2]], (rows + 3) / 4, 64)

-> enqueue_mamba_quad(lyr)
  cs_in = lyr[:cs_a]
  cs_out = lyr[:cs_b]
  ss_in = lyr[:ss_a]
  ss_out = lyr[:ss_b]
  if lyr[:ping] == 1
    cs_in = lyr[:cs_b]
    cs_out = lyr[:cs_a]
    ss_in = lyr[:ss_b]
    ss_out = lyr[:ss_a]
  enqueue_rms([x_quad, lyr[:in_norm], xn_quad, 4])
  dependency_barrier()
  enqueue_scaled_quad([lyr[:qkv], xn_quad, qkv_quad_tmp, HIDDEN, QKV_DIM])
  enqueue_scaled_quad([lyr[:z], xn_quad, z_quad_tmp, HIDDEN, V_DIM])
  metal_dispatch_groups(queue, quad_bf16_pipe,
    [lyr[:a], xn_quad, a_quad_tmp, HIDDEN, HV], HV, 32)
  metal_dispatch_groups(queue, quad_bf16_pipe,
    [lyr[:b], xn_quad, b_quad_tmp, HIDDEN, HV], HV, 32)
  dependency_barrier()
  metal_dispatch_n(queue, conv_quad_pipe,
    [lyr[:conv], cs_in, qkv_quad_tmp, conv_quad_tmp,
     lyr[:cs_mid], lyr[:cs_mid2], lyr[:cs_mid3], cs_out, QKV_DIM], QKV_DIM)
  dependency_barrier()
  metal_dispatch_n(queue, copy_quad_slice_pipe,
    [conv_quad_tmp, mq_quad_tmp, QKV_DIM, Q_DIM, 0, Q_DIM], 4 * Q_DIM)
  metal_dispatch_n(queue, copy_quad_slice_pipe,
    [conv_quad_tmp, mk_quad_tmp, QKV_DIM, K_DIM, Q_DIM, K_DIM], 4 * K_DIM)
  metal_dispatch_n(queue, copy_quad_slice_pipe,
    [conv_quad_tmp, mv_quad_tmp, QKV_DIM, V_DIM, Q_DIM + K_DIM, V_DIM], 4 * V_DIM)
  dependency_barrier()
  metal_dispatch_groups(queue, phn_pipe,
    [mq_quad_tmp, q_norm_scale, DK, ~1.0 / DK, EPS], 4 * HK, 32)
  metal_dispatch_groups(queue, phn_pipe,
    [mk_quad_tmp, k_norm_scale, DK, ~1.0 / DK, EPS], 4 * HK, 32)
  metal_dispatch_n(queue, g_pipe,
    [a_quad_tmp, lyr[:alog], lyr[:dtb], g_quad_tmp, HV, 4 * HV], 4 * HV)
  metal_dispatch_n(queue, sigmoid_pipe,
    [b_quad_tmp, beta_quad_tmp, 4 * HV], 4 * HV)
  dependency_barrier()
  metal_dispatch_3d(queue, delta_quad_pipe,
    [mq_quad_tmp, mk_quad_tmp, mv_quad_tmp, g_quad_tmp,
     beta_quad_tmp, ss_in, delta_quad_tmp, lyr[:ss_mid],
     lyr[:ss_mid2], lyr[:ss_mid3], ss_out, HK, HV, DK, DV],
    1, DV / 4, HV, 32, 4, 1)
  dependency_barrier()
  metal_dispatch_groups(queue, rng_pipe,
    [delta_quad_tmp, z_quad_tmp, lyr[:linear_norm],
     mamba_norm_quad_tmp, DV, EPS], 4 * HV, 32)
  dependency_barrier()
  enqueue_residual_quad(
    [lyr[:out], mamba_norm_quad_tmp, x_quad, V_DIM, HIDDEN])
  dependency_barrier()
  lyr[:ping] = 1 - lyr[:ping]

-> enqueue_full_quad(spec)
  lyr = spec[0]
  pos_start = spec[1]
  enqueue_rms([x_quad, lyr[:in_norm], xn_quad, 4])
  dependency_barrier()
  enqueue_scaled_quad([lyr[:q], xn_quad, qfull_quad_tmp, HIDDEN, QFULL_DIM])
  enqueue_scaled_quad([lyr[:k], xn_quad, k_quad_tmp, HIDDEN, KV_DIM])
  enqueue_scaled_quad([lyr[:v], xn_quad, v_quad_tmp, HIDDEN, KV_DIM])
  dependency_barrier()
  metal_dispatch_n(queue, split_quad_pipe,
    [qfull_quad_tmp, queries_quad_tmp, attn_gate_quad_tmp,
     N_HEADS, HEAD_DIM], 4 * ATTN_DIM)
  dependency_barrier()
  metal_dispatch_groups(queue, phn_rope_quad_pipe,
    [queries_quad_tmp, lyr[:qn], cos_quad_tmp, sin_quad_tmp,
     HEAD_DIM, ROT_HALF, N_HEADS, ~1.0 / HEAD_DIM, EPS], 4 * N_HEADS, 32)
  metal_dispatch_groups(queue, phn_rope_quad_pipe,
    [k_quad_tmp, lyr[:kn], cos_quad_tmp, sin_quad_tmp,
     HEAD_DIM, ROT_HALF, N_KV_HEADS, ~1.0 / HEAD_DIM, EPS], 4 * N_KV_HEADS, 32)
  dependency_barrier()
  metal_dispatch_n(queue, kv_write_quad_pipe,
    [k_quad_tmp, v_quad_tmp, lyr[:k_cache], lyr[:v_cache],
     pos_start, KV_DIM], 4 * KV_DIM)
  dependency_barrier()
  metal_dispatch_groups(queue, sdpa_quad_pipe,
    [queries_quad_tmp, lyr[:k_cache], lyr[:v_cache], attn_quad_tmp,
     GQA, pos_start, N_HEADS, KV_DIM, ATTN_SCALE], 4 * N_HEADS, 256)
  dependency_barrier()
  metal_dispatch_n(queue, gate_pipe,
    [attn_quad_tmp, attn_gate_quad_tmp, 4 * ATTN_DIM], 4 * ATTN_DIM)
  dependency_barrier()
  enqueue_residual_quad(
    [lyr[:out], attn_quad_tmp, x_quad, ATTN_DIM, HIDDEN])
  dependency_barrier()

-> enqueue_ffn_quad(lyr)
  enqueue_rms([x_quad, lyr[:post_norm], xn_quad, 4])
  dep_barrier_on([xn_quad])
  enqueue_scaled_quad([lyr[:gate], xn_quad, gate_quad_tmp, HIDDEN, FFN])
  enqueue_scaled_quad([lyr[:up], xn_quad, up_quad_tmp, HIDDEN, FFN])
  dep_barrier_on([gate_quad_tmp, up_quad_tmp])
  metal_dispatch_n(queue, silu_pipe,
    [gate_quad_tmp, up_quad_tmp, hidden_quad_tmp, 4 * FFN], 4 * FFN)
  dep_barrier_on([hidden_quad_tmp])
  enqueue_residual_quad(
    [lyr[:down], hidden_quad_tmp, x_quad, FFN, HIDDEN])
  dep_barrier_on([x_quad])

# A committed MTP-history row only needs to append the attention K/V derived
# from the fused embedding/target-hidden input. Q, attention output, the MLP,
# final norm, and vocabulary projection are dead for this row.
-> forward_quad(spec)
  profile_t0 = profile_components ? ccall("__w_clock_ms") : ~0.0
  token0 = spec[0]
  token1 = spec[1]
  token2 = spec[2]
  token3 = spec[3]
  pos_start = spec[4]
  # spec[5] set => token slots 2,3 were filled device-side by deferred
  # drafts (copy_i32_at); the host must not clobber them.
  dev_slots23 = spec.size() > 5 && spec[5]
  build_rope_quad(pos_start)
  metal_buffer_write_i32(token_quad_buf, 0, token0)
  metal_buffer_write_i32(token_quad_buf, 1, token1)
  if !dev_slots23
    metal_buffer_write_i32(token_quad_buf, 2, token2)
    metal_buffer_write_i32(token_quad_buf, 3, token3)
  metal_batch_begin_concurrent(queue)
  metal_dispatch_n(queue, quad_embed_pipe,
    [embed_w, x_quad, token_quad_buf, HIDDEN], 4 * HIDDEN)
  dependency_barrier()
  li = 0
  while li < N_LAYERS
    lyr = layers[li]
    if lyr[:kind] == "mamba"
      enqueue_mamba_quad(lyr)
    else
      enqueue_full_quad([lyr, pos_start])
    enqueue_ffn_quad(lyr)
    li = li + 1
  enqueue_rms([x_quad, final_norm, xn_quad, 4])
  dependency_barrier()
  enqueue_scaled_quad([lm_head, xn_quad, logits_quad, HIDDEN, N_VOCAB])
  dependency_barrier()
  enqueue_argmax([logits_quad, argmax_quad_out, 4])
  metal_batch_commit(queue)
  result = [metal_buffer_read_i32(argmax_quad_out, 0),
    metal_buffer_read_i32(argmax_quad_out, 1),
    metal_buffer_read_i32(argmax_quad_out, 2),
    metal_buffer_read_i32(argmax_quad_out, 3)]
  if profile_components
    profile_stats[5] = profile_stats[5] + ccall("__w_clock_ms") - profile_t0
    profile_stats[6] = profile_stats[6] + 1
  result

# Batched prefill: run 3 prompt tokens through the target backbone in ONE
# weight stream (the cross-row triplet kernels amortize the 18 GB weight read
# across all 3 rows, bit-exact by row independence -- the same property that
# makes decode verify exact). Builds KV for positions pos..pos+2 and advances
# the gated-delta state, exactly like 3 serial forwards, at ~1/3 the memory
# traffic. Triplet buffers are allocated in every MTP mode (decode uses
# forward_triplet), unlike the quad buffers. Per-token pre-final-norm hidden
# stays in x_triplet for the head-history appends; lm_head skipped unless last.
-> forward_prefill_chunk(spec)
  profile_t0 = profile_components ? ccall("__w_clock_ms") : ~0.0
  pos_start = spec[3]
  want_last = spec[4]
  build_rope_triplet(pos_start)
  metal_buffer_write_i32(token_triplet_buf, 0, spec[0])
  metal_buffer_write_i32(token_triplet_buf, 1, spec[1])
  metal_buffer_write_i32(token_triplet_buf, 2, spec[2])
  metal_batch_begin_concurrent(queue)
  metal_dispatch_n(queue, triplet_embed_pipe,
    [embed_w, x_triplet, token_triplet_buf, HIDDEN], 3 * HIDDEN)
  dependency_barrier()
  li = 0
  while li < N_LAYERS
    lyr = layers[li]
    if lyr[:kind] == "mamba"
      enqueue_mamba_triplet(lyr)
    else
      enqueue_full_triplet([lyr, pos_start])
    enqueue_ffn_triplet(lyr)
    li = li + 1
  result = -1
  if want_last
    enqueue_rms([x_triplet, final_norm, xn_triplet, 3])
    dependency_barrier()
    enqueue_scaled_triplet([lm_head, xn_triplet, logits_triplet, HIDDEN, N_VOCAB])
    dependency_barrier()
    enqueue_argmax([logits_triplet, argmax_triplet_out, 3])
    metal_batch_commit(queue)
    result = metal_buffer_read_i32(argmax_triplet_out, 2)
  else
    metal_batch_commit(queue)
  if profile_components && profile_stats[0] == 1
    profile_stats[3] = profile_stats[3] + ccall("__w_clock_ms") - profile_t0
    profile_stats[4] = profile_stats[4] + 3
  result

-> copy_hidden_multi_row(row)
  metal_batch_begin(queue)
  metal_dispatch_n(queue, copy_pair_row_pipe,
    [x_multi, backbone_hidden, row, HIDDEN], HIDDEN)
  metal_batch_commit(queue)

-> copy_hidden_quad_row(row)
  profile_t0 = profile_components ? ccall("__w_clock_ms") : ~0.0
  metal_batch_begin(queue)
  metal_dispatch_n(queue, copy_pair_row_pipe,
    [x_quad, backbone_hidden, row, HIDDEN], HIDDEN)
  metal_batch_commit(queue)
  if profile_components
    profile_stats[11] = profile_stats[11] + ccall("__w_clock_ms") - profile_t0
    profile_stats[12] = profile_stats[12] + 1

-> rollback_pair_states
  profile_t0 = profile_components ? ccall("__w_clock_ms") : ~0.0
  li = 0
  while li < N_LAYERS
    lyr = layers[li]
    if lyr[:kind] == "mamba"
      if lyr[:ping] == 1
        tmp = lyr[:cs_b]
        lyr[:cs_b] = lyr[:cs_mid]
        lyr[:cs_mid] = tmp
        tmp = lyr[:ss_b]
        lyr[:ss_b] = lyr[:ss_mid]
        lyr[:ss_mid] = tmp
      else
        tmp = lyr[:cs_a]
        lyr[:cs_a] = lyr[:cs_mid]
        lyr[:cs_mid] = tmp
        tmp = lyr[:ss_a]
        lyr[:ss_a] = lyr[:ss_mid]
        lyr[:ss_mid] = tmp
    li = li + 1
  if profile_components
    profile_stats[13] = profile_stats[13] + ccall("__w_clock_ms") - profile_t0
    profile_stats[14] = profile_stats[14] + 1

-> rollback_triplet_states(accepted_count)
  profile_t0 = profile_components ? ccall("__w_clock_ms") : ~0.0
  li = 0
  while li < N_LAYERS
    lyr = layers[li]
    if lyr[:kind] == "mamba"
      if accepted_count == 0
        chosen_cs = lyr[:cs_mid]
        chosen_ss = lyr[:ss_mid]
      else
        chosen_cs = lyr[:cs_mid2]
        chosen_ss = lyr[:ss_mid2]
      if lyr[:ping] == 1
        old_cs = lyr[:cs_b]
        old_ss = lyr[:ss_b]
        lyr[:cs_b] = chosen_cs
        lyr[:ss_b] = chosen_ss
      else
        old_cs = lyr[:cs_a]
        old_ss = lyr[:ss_a]
        lyr[:cs_a] = chosen_cs
        lyr[:ss_a] = chosen_ss
      if accepted_count == 0
        lyr[:cs_mid] = old_cs
        lyr[:ss_mid] = old_ss
      else
        lyr[:cs_mid2] = old_cs
        lyr[:ss_mid2] = old_ss
    li = li + 1
  if profile_components
    profile_stats[13] = profile_stats[13] + ccall("__w_clock_ms") - profile_t0
    profile_stats[14] = profile_stats[14] + 1

-> rollback_quad_states(accepted_count)
  # A width-4 verify can be accepted at prefix 0, 1 or 2 (a full 3-accept needs
  # no rollback), so it selects among three published interior snapshots.
  profile_t0 = profile_components ? ccall("__w_clock_ms") : ~0.0
  li = 0
  while li < N_LAYERS
    lyr = layers[li]
    if lyr[:kind] == "mamba"
      if accepted_count == 0
        chosen_cs = lyr[:cs_mid]
        chosen_ss = lyr[:ss_mid]
      elsif accepted_count == 1
        chosen_cs = lyr[:cs_mid2]
        chosen_ss = lyr[:ss_mid2]
      else
        chosen_cs = lyr[:cs_mid3]
        chosen_ss = lyr[:ss_mid3]
      if lyr[:ping] == 1
        old_cs = lyr[:cs_b]
        old_ss = lyr[:ss_b]
        lyr[:cs_b] = chosen_cs
        lyr[:ss_b] = chosen_ss
      else
        old_cs = lyr[:cs_a]
        old_ss = lyr[:ss_a]
        lyr[:cs_a] = chosen_cs
        lyr[:ss_a] = chosen_ss
      if accepted_count == 0
        lyr[:cs_mid] = old_cs
        lyr[:ss_mid] = old_ss
      elsif accepted_count == 1
        lyr[:cs_mid2] = old_cs
        lyr[:ss_mid2] = old_ss
      else
        lyr[:cs_mid3] = old_cs
        lyr[:ss_mid3] = old_ss
    li = li + 1
  if profile_components
    profile_stats[13] = profile_stats[13] + ccall("__w_clock_ms") - profile_t0
    profile_stats[14] = profile_stats[14] + 1

# ---- runtime-width block verify: n <= MULTI_MAX rows in one causal pass ----
# The kernels are decode_multi.metal (per-token arithmetic of the quad path,
# so a width-n verify is bit-identical to n serial steps); the dense NVFP4
# projections come from the wide cross-row ladder, chosen per width by
# multi_pipe_key. Recurrent state uses tape replay: the verify writes only
# its final state, and rollback re-runs the accepted prefix from the intact
# ping-pong input.
-> build_rope_multi(pos_start, n)
  token = 0
  while token < n
    i = 0
    while i < ROT_HALF
      theta = Math.exp(log_rope * (~0.0 - i * rope_power))
      angle = (pos_start + token) * theta
      metal_buffer_write_f32(cos_multi_tmp, token * ROT_HALF + i, Math.cos(angle))
      metal_buffer_write_f32(sin_multi_tmp, token * ROT_HALF + i, Math.sin(angle))
      i = i + 1
    token = token + 1

-> multi_pipe_key(n, kdim, residual)
  auto_key = "b" + n.to_s + "_"
  if n > MULTI_WIDE_MAX
    # Only the GEMM covers widths past the wide-GEMV ladder.
    return auto_key + "g" + (residual ? "_res" : "")
  if n == 8
    auto_key = auto_key + (kdim == FFN ? "s4" : "s2")
  elsif n >= 6
    auto_key = auto_key + (kdim == FFN ? "r2" : "r1")
  else
    auto_key = auto_key + (kdim == FFN ? "r4" : "r2")
  if residual then auto_key = auto_key + "_res"
  if multi_variant == "auto" then return auto_key
  key = "b" + n.to_s + "_" + multi_variant + (residual ? "_res" : "")
  # A forced rung that does not exist at this width (the split rungs are
  # b6/b8 only) falls back to the auto choice for that width.
  if multi_pipes[key] == nil then return auto_key
  key

# One projection on the Neural Accelerators for a width the simdgroup ladder
# cannot serve. Stages the f32 activations to f16 (matmul2d takes fp16
# operands), then runs the NA GEMM. `residual` folds the result into `output`
# with a separate add, since the kernel has no accumulate-into-C mode.
#
# The scratch is shared across projections, so each write is fenced on BOTH
# sides: the leading barrier is the WAR against the previous projection's
# still-reading GEMM, the trailing one the RAW for this one.
-> na_scaled_multi(w, input, output, kdim, ndim, n, residual)
  na_stage(input, na_in_h16, n, kdim)
  if !residual
    na_proj(w, na_in_h16, output, kdim, ndim, n)
    return
  if ndim > HIDDEN
    raise "na residual projection ndim " + ndim.to_s + " exceeds na_out_tmp width " + HIDDEN.to_s
  dep_barrier_on([na_out_tmp])
  na_proj(w, na_in_h16, na_out_tmp, kdim, ndim, n)
  dep_barrier_on([na_out_tmp])
  metal_dispatch_n(queue, add_pipe, [output, na_out_tmp, n * ndim], n * ndim)

-> enqueue_scaled_multi(spec)
  w = spec[0]
  input = spec[1]
  output = spec[2]
  kdim = spec[3]
  rows = spec[4]
  n = spec[5]
  if n > MULTI_LADDER_MAX || g_na_attn
    na_scaled_multi(w, input, output, kdim, rows, n, false)
    return
  key = multi_pipe_key(n, kdim, false)
  if multi_rows[key] == 0
    # simdgroup-matrix GEMM rung: 32 output rows per 128-thread group.
    metal_dispatch_groups(queue, multi_pipes[key],
      [w[0], w[1], input, output, kdim, rows, w[2], n], (rows + 31) / 32, 128)
    return
  per_group = 2 * multi_rows[key]
  metal_dispatch_groups(queue, multi_pipes[key],
    [w[0], w[1], input, output, kdim, rows, w[2]], (rows + per_group - 1) / per_group, 64)

-> enqueue_residual_multi(spec)
  w = spec[0]
  input = spec[1]
  residual = spec[2]
  kdim = spec[3]
  rows = spec[4]
  n = spec[5]
  if n > MULTI_LADDER_MAX || g_na_attn
    na_scaled_multi(w, input, residual, kdim, rows, n, true)
    return
  key = multi_pipe_key(n, kdim, true)
  if multi_rows[key] == 0
    metal_dispatch_groups(queue, multi_pipes[key],
      [w[0], w[1], input, residual, kdim, rows, w[2], n], (rows + 31) / 32, 128)
    return
  per_group = 2 * multi_rows[key]
  metal_dispatch_groups(queue, multi_pipes[key],
    [w[0], w[1], input, residual, kdim, rows, w[2]], (rows + per_group - 1) / per_group, 64)

-> enqueue_mamba_multi(lyr, n)
  cs_in = lyr[:cs_a]
  cs_out = lyr[:cs_b]
  ss_in = lyr[:ss_a]
  ss_out = lyr[:ss_b]
  if lyr[:ping] == 1
    cs_in = lyr[:cs_b]
    cs_out = lyr[:cs_a]
    ss_in = lyr[:ss_b]
    ss_out = lyr[:ss_a]
  enqueue_rms([x_multi, lyr[:in_norm], xn_multi, n])
  dependency_barrier()
  # qkv and z read the SAME normalized activations, so the f16 staging is
  # hoisted out of both: one conversion, then two NA GEMMs that run
  # concurrently instead of being serialized by a shared staging buffer.
  if g_na_attn
    na_stage(xn_multi, xn_h16, n, HIDDEN)
    na_proj(lyr[:qkv], xn_h16, lyr[:qkv_m], HIDDEN, QKV_DIM, n)
    na_proj(lyr[:z], xn_h16, z_multi_tmp, HIDDEN, V_DIM, n)
  else
    enqueue_scaled_multi([lyr[:qkv], xn_multi, lyr[:qkv_m], HIDDEN, QKV_DIM, n])
    enqueue_scaled_multi([lyr[:z], xn_multi, z_multi_tmp, HIDDEN, V_DIM, n])
  metal_dispatch_groups(queue, multi_bf16_pipe,
    [lyr[:a], xn_multi, a_multi_tmp, HIDDEN, HV, n], HV, 32)
  metal_dispatch_groups(queue, multi_bf16_pipe,
    [lyr[:b], xn_multi, b_multi_tmp, HIDDEN, HV, n], HV, 32)
  dependency_barrier()
  metal_dispatch_n(queue, conv_multi_pipe,
    [lyr[:conv], cs_in, lyr[:qkv_m], conv_multi_tmp, cs_out, QKV_DIM, n], QKV_DIM)
  dependency_barrier()
  metal_dispatch_n(queue, copy_multi_slice_pipe,
    [conv_multi_tmp, lyr[:mq_m], QKV_DIM, Q_DIM, 0, Q_DIM, n], n * Q_DIM)
  metal_dispatch_n(queue, copy_multi_slice_pipe,
    [conv_multi_tmp, lyr[:mk_m], QKV_DIM, K_DIM, Q_DIM, K_DIM, n], n * K_DIM)
  metal_dispatch_n(queue, copy_multi_slice_pipe,
    [conv_multi_tmp, lyr[:mv_m], QKV_DIM, V_DIM, Q_DIM + K_DIM, V_DIM, n], n * V_DIM)
  dependency_barrier()
  metal_dispatch_groups(queue, phn_pipe,
    [lyr[:mq_m], q_norm_scale, DK, ~1.0 / DK, EPS], n * HK, 32)
  metal_dispatch_groups(queue, phn_pipe,
    [lyr[:mk_m], k_norm_scale, DK, ~1.0 / DK, EPS], n * HK, 32)
  metal_dispatch_n(queue, g_pipe,
    [a_multi_tmp, lyr[:alog], lyr[:dtb], lyr[:g_m], HV, n * HV], n * HV)
  metal_dispatch_n(queue, sigmoid_pipe,
    [b_multi_tmp, lyr[:beta_m], n * HV], n * HV)
  dependency_barrier()
  metal_dispatch_3d(queue, delta_multi_pipe,
    [lyr[:mq_m], lyr[:mk_m], lyr[:mv_m], lyr[:g_m], lyr[:beta_m],
     ss_in, delta_multi_tmp, ss_out, HK, HV, DK, DV, n],
    1, DV / 4, HV, 32, 4, 1)
  dependency_barrier()
  metal_dispatch_groups(queue, rng_pipe,
    [delta_multi_tmp, z_multi_tmp, lyr[:linear_norm],
     mamba_norm_multi_tmp, DV, EPS], n * HV, 32)
  dependency_barrier()
  enqueue_residual_multi(
    [lyr[:out], mamba_norm_multi_tmp, x_multi, V_DIM, HIDDEN, n])
  dependency_barrier()
  lyr[:ping] = 1 - lyr[:ping]

-> enqueue_full_multi(spec)
  lyr = spec[0]
  pos_start = spec[1]
  n = spec[2]
  enqueue_rms([x_multi, lyr[:in_norm], xn_multi, n])
  dependency_barrier()
  # q, k and v read the SAME normalized activations: stage to f16 once, then
  # let the three NA GEMMs run concurrently.
  if g_na_attn
    na_stage(xn_multi, xn_h16, n, HIDDEN)
    na_proj(lyr[:q], xn_h16, qfull_multi_tmp, HIDDEN, QFULL_DIM, n)
    na_proj(lyr[:k], xn_h16, k_multi_tmp, HIDDEN, KV_DIM, n)
    na_proj(lyr[:v], xn_h16, v_multi_tmp, HIDDEN, KV_DIM, n)
  else
    enqueue_scaled_multi([lyr[:q], xn_multi, qfull_multi_tmp, HIDDEN, QFULL_DIM, n])
    enqueue_scaled_multi([lyr[:k], xn_multi, k_multi_tmp, HIDDEN, KV_DIM, n])
    enqueue_scaled_multi([lyr[:v], xn_multi, v_multi_tmp, HIDDEN, KV_DIM, n])
  dependency_barrier()
  metal_dispatch_n(queue, split_multi_pipe,
    [qfull_multi_tmp, queries_multi_tmp, attn_gate_multi_tmp,
     N_HEADS, HEAD_DIM, n], n * ATTN_DIM)
  dependency_barrier()
  metal_dispatch_groups(queue, phn_rope_multi_pipe,
    [queries_multi_tmp, lyr[:qn], cos_multi_tmp, sin_multi_tmp,
     HEAD_DIM, ROT_HALF, N_HEADS, ~1.0 / HEAD_DIM, EPS, n], n * N_HEADS, 32)
  metal_dispatch_groups(queue, phn_rope_multi_pipe,
    [k_multi_tmp, lyr[:kn], cos_multi_tmp, sin_multi_tmp,
     HEAD_DIM, ROT_HALF, N_KV_HEADS, ~1.0 / HEAD_DIM, EPS, n], n * N_KV_HEADS, 32)
  dependency_barrier()
  metal_dispatch_n(queue, kv_write_multi_pipe,
    [k_multi_tmp, v_multi_tmp, lyr[:k_cache], lyr[:v_cache],
     pos_start, KV_DIM, n], n * KV_DIM)
  dependency_barrier()
  metal_dispatch_groups(queue, sdpa_multi_pipe,
    [queries_multi_tmp, lyr[:k_cache], lyr[:v_cache], attn_multi_tmp,
     GQA, pos_start, N_HEADS, KV_DIM, ATTN_SCALE, n], n * N_HEADS, 256)
  dependency_barrier()
  metal_dispatch_n(queue, gate_pipe,
    [attn_multi_tmp, attn_gate_multi_tmp, n * ATTN_DIM], n * ATTN_DIM)
  dependency_barrier()
  enqueue_residual_multi(
    [lyr[:out], attn_multi_tmp, x_multi, ATTN_DIM, HIDDEN, n])
  dependency_barrier()

# One projection on the M5 Neural Accelerators (mpp::tensor_ops::matmul2d),
# dispatched from the CLASSIC compute encoder into the batch already open.
#
# in_buf: f16 activations [MULTI_MAX][kdim]; out_buf: f32 [MULTI_MAX][ndim].
# The cooperative-tensor store does NOT clip to the extents, so the row count
# handed to the kernel is rounded UP to the M tile and the dispatch covers
# exactly those rows: the scratch buffers carry MULTI_MAX rows, so rows in
# [n, mrows) are computed and unused, and mrows <= MULTI_MAX always because
# MULTI_MAX is itself tile-aligned. Every projection in this model satisfies
# the other two alignment rules already (kdim % 128 == 0, ndim % 64 == 0).
-> na_proj(w, in_buf, out_buf, kdim, ndim, n)
  if n <= NA_MT64
    metal_dispatch_3d(queue, na_m64_pipe,
      [in_buf, w[0], w[1], out_buf, kdim, w[2], NA_MT64, ndim],
      1, ndim / 64, 1, 128, 1, 1)
    return
  mrows = ((n + NA_MT - 1) / NA_MT) * NA_MT
  metal_dispatch_3d(queue, na_pipe,
    [in_buf, w[0], w[1], out_buf, kdim, w[2], mrows, ndim],
    mrows / NA_MT, ndim / 64, 1, 128, 1, 1)

# Stage n rows of an f32 activation block as f16 for the NA GEMMs (matmul2d
# takes fp16 operands). Fenced on BOTH sides: the leading barrier is the WAR
# against whatever GEMM last read this staging buffer, the trailing one the
# RAW for the GEMMs about to read it.
-> na_stage(src, dst, n, dim)
  dep_barrier_on([dst])
  metal_dispatch_n(queue, f32_to_f16_pipe, [src, dst, n * dim], n * dim)
  dep_barrier_on([dst])

# Neural-Accelerator FFN (gemm-prefill). Every dispatch -- the two f32->f16
# activation stagings, the three NA GEMMs, silu and the residual add -- lands
# in the SAME concurrent command buffer, ordered by scoped resource barriers.
# Numerically parity-safe (f16 acts preserve argmax; see the tuning doc).
-> ffn_na(lyr, n)
  na_stage(xn_multi, xn_h16, n, HIDDEN)
  na_proj(lyr[:gate], xn_h16, gate_multi_tmp, HIDDEN, FFN, n)
  na_proj(lyr[:up], xn_h16, up_multi_tmp, HIDDEN, FFN, n)
  dep_barrier_on([gate_multi_tmp, up_multi_tmp])
  metal_dispatch_n(queue, silu_pipe,
    [gate_multi_tmp, up_multi_tmp, hidden_multi_tmp, n * FFN], n * FFN)
  dep_barrier_on([hidden_multi_tmp])
  na_stage(hidden_multi_tmp, h_h16, n, FFN)
  na_proj(lyr[:down], h_h16, down_na_tmp, FFN, HIDDEN, n)
  dep_barrier_on([down_na_tmp])
  metal_dispatch_n(queue, add_pipe, [x_multi, down_na_tmp, n * HIDDEN], n * HIDDEN)
  dep_barrier_on([x_multi])

-> enqueue_ffn_multi(lyr, n)
  enqueue_rms([x_multi, lyr[:post_norm], xn_multi, n])
  dep_barrier_on([xn_multi])
  if g_na_ffn
    ffn_na(lyr, n)
  else
    enqueue_scaled_multi([lyr[:gate], xn_multi, gate_multi_tmp, HIDDEN, FFN, n])
    enqueue_scaled_multi([lyr[:up], xn_multi, up_multi_tmp, HIDDEN, FFN, n])
    dep_barrier_on([gate_multi_tmp, up_multi_tmp])
    metal_dispatch_n(queue, silu_pipe,
      [gate_multi_tmp, up_multi_tmp, hidden_multi_tmp, n * FFN], n * FFN)
    dep_barrier_on([hidden_multi_tmp])
    enqueue_residual_multi(
      [lyr[:down], hidden_multi_tmp, x_multi, FFN, HIDDEN, n])
    dep_barrier_on([x_multi])

# spec = [tokens | nil, pos_start, n, want_taps]. tokens (an n-array of ids)
# is written into token_multi_buf; pass nil when a device-side drafter has
# already filled the slots. Returns the n greedy argmax ids. With want_taps
# the five DFlash2 taps of every row land in ctx_hidden rows 0..n-1.
-> forward_multi(spec)
  profile_t0 = profile_components ? ccall("__w_clock_ms") : ~0.0
  tokens = spec[0]
  pos_start = spec[1]
  n = spec[2]
  want_taps = spec.size() > 3 && spec[3]
  # spec[4] = "last": only the final row's argmax, via the serial lm_head path
  # (prefill); spec[4] = "none": no logits at all (prefill chunk that is not
  # the prompt's end). Default: every row's argmax (verify).
  logits_mode = spec.size() > 4 ? spec[4] : "all"
  if n < 1 || n > MULTI_MAX then raise "forward_multi width " + n.to_s + " out of range"
  if logits_mode == "all" && n > LOGITS_MULTI_MAX
    raise "forward_multi asked for " + n.to_s + " rows of logits but the scratch holds " + LOGITS_MULTI_MAX.to_s
  if tokens != nil
    i = 0
    while i < n
      metal_buffer_write_i32(token_multi_buf, i, tokens[i])
      i = i + 1
  build_rope_multi(pos_start, n)
  metal_batch_begin_concurrent(queue)
  metal_dispatch_n(queue, multi_embed_pipe,
    [embed_w, x_multi, token_multi_buf, HIDDEN, n], n * HIDDEN)
  dependency_barrier()
  li = 0
  while li < N_LAYERS
    lyr = layers[li]
    if lyr[:kind] == "mamba"
      enqueue_mamba_multi(lyr, n)
    else
      enqueue_full_multi([lyr, pos_start, n])
    enqueue_ffn_multi(lyr, n)
    if want_taps
      t = 0
      while t < 5
        if tap_layers[t] == li
          metal_dispatch_n(queue, copy_taps_multi_pipe,
            [x_multi, ctx_hidden, HIDDEN, 5, t, pos_start, n], n * HIDDEN)
        t = t + 1
    li = li + 1
  result = []
  if logits_mode == "all"
    enqueue_rms([x_multi, final_norm, xn_multi, n])
    dependency_barrier()
    enqueue_scaled_multi([lm_head, xn_multi, logits_multi, HIDDEN, N_VOCAB, n])
    dependency_barrier()
    enqueue_argmax([logits_multi, argmax_multi_out, n])
    metal_batch_commit(queue)
    i = 0
    while i < n
      result.push(metal_buffer_read_i32(argmax_multi_out, i))
      i = i + 1
  elsif logits_mode == "last"
    # Stage the last row into the serial scratch so the vocabulary projection
    # and argmax are exactly the serial decode's.
    metal_dispatch_n(queue, copy_f32_at_pipe,
      [x_multi, x, (n - 1) * HIDDEN, 0, HIDDEN], HIDDEN)
    dependency_barrier()
    enqueue_rms([x, final_norm, xn, 1])
    dependency_barrier()
    enqueue_scaled([lm_head, xn, logits, HIDDEN, N_VOCAB])
    dependency_barrier()
    enqueue_argmax([logits, argmax_out, 1])
    metal_batch_commit(queue)
    result.push(metal_buffer_read_i32(argmax_out, 0))
  else
    metal_batch_commit(queue)
  if profile_components
    profile_stats[5] = profile_stats[5] + ccall("__w_clock_ms") - profile_t0
    profile_stats[6] = profile_stats[6] + 1
  result

# After a width-n verify accepted `accepted_count` drafts (so accepted_count+1
# rows are committed), rebuild every gated-delta layer's conv and recurrent
# state for exactly those rows by replaying them from the pre-verify state,
# which the verify left intact in the other ping-pong buffer. A full accept
# (accepted_count == n - 1) needs nothing: the verify's final state IS it.
-> rollback_multi_states(accepted_count, n)
  if accepted_count >= n - 1 then return
  profile_t0 = profile_components ? ccall("__w_clock_ms") : ~0.0
  keep = accepted_count + 1
  metal_batch_begin_concurrent(queue)
  li = 0
  while li < N_LAYERS
    lyr = layers[li]
    if lyr[:kind] == "mamba"
      # The verify flipped ping; its output is now the "in" slot and the
      # pre-verify state is the other one.
      if lyr[:ping] == 1
        pre_cs = lyr[:cs_a]
        out_cs = lyr[:cs_b]
        pre_ss = lyr[:ss_a]
        out_ss = lyr[:ss_b]
      else
        pre_cs = lyr[:cs_b]
        out_cs = lyr[:cs_a]
        pre_ss = lyr[:ss_b]
        out_ss = lyr[:ss_a]
      metal_dispatch_n(queue, conv_replay_pipe,
        [pre_cs, lyr[:qkv_m], out_cs, QKV_DIM, keep], QKV_DIM)
      metal_dispatch_3d(queue, delta_multi_pipe,
        [lyr[:mq_m], lyr[:mk_m], lyr[:mv_m], lyr[:g_m], lyr[:beta_m],
         pre_ss, delta_multi_tmp, out_ss, HK, HV, DK, DV, keep],
        1, DV / 4, HV, 32, 4, 1)
    li = li + 1
  metal_batch_commit(queue)
  if profile_components
    profile_stats[13] = profile_stats[13] + ccall("__w_clock_ms") - profile_t0
    profile_stats[14] = profile_stats[14] + 1

# ---- DFlash2 drafter (z-lab/Qwen3.8-27B-DFlash2): weights, context, block ----
# A 5-layer qwen3 transformer that fills [anchor, MASK x (n-1)] in one pass,
# conditioned on five target taps per committed position (ctx_hidden rows,
# indexed by absolute position). Weights are bf16 and mmap'd; everything
# runs in f32. Kernels: dflash2_draft.metal (+ decode_multi.metal helpers).
DRAFT_PATH = "/Users/erik/.cache/huggingface/hub/models--z-lab--Qwen3.8-27B-DFlash2/snapshots/50307d4c4cde6860d4eee73e2547cd786fe8e8a4/model.safetensors"
DRAFT_QUANT_PATH = "/Users/erik/.cache/tungsten/dflash2-nvfp4/model.safetensors"
D_LAYERS = 5
D_HEADS = 32
D_KV = 8
D_HD = 128
D_QDIM = D_HEADS * D_HD
D_KVDIM = D_KV * D_HD
D_RANK = 256
D_TOPK = 16
D_MASK = 248070
D_WINDOW = 2048
D_ROT_HALF = D_HD / 2
D_KP = 1280
D_CTX_DIM = 5 * HIDDEN
D_SCALE = ~1.0 / Math.sqrt(~0.0 + D_HD)
d_log_rope = Math.log(~10000000.0)
d_rope_power = ~2.0 / D_HD

dst = nil
dlayers = []

-> draft_tensor(name)
  t = dst.tensor(name)
  metal_buffer_for_mmap(device, dst.mmap, t[:byte_offset], t[:byte_length])

# A projection weight: bf16 buffer, or the NVFP4 [packed, scale, global]
# triple when the quantized drafter is selected.
-> draft_proj(name)
  if draft_quant
    [draft_tensor(name), draft_tensor(name + ".scale"), draft_tensor(name + ".global_scale")]
  else
    draft_tensor(name)

# DFlash2 drafter weights (bf16, mmap'd) and per-layer draft K/V caches.
if dflash2_enabled
  dst = Tungsten:Llama:Safetensors.new(draft_quant ? DRAFT_QUANT_PATH : DRAFT_PATH)
  << "dflash2 drafter: " + dst.count().to_s + " tensors, block " + dflash2_block.to_s + (draft_quant ? ", nvfp4" : ", bf16")
  d_fc = draft_proj("fc.weight")
  d_hidden_norm = metal_buffer(device, HIDDEN * 4)
  d_norm = metal_buffer(device, HIDDEN * 4)
  draft_load_f32(["hidden_norm.weight", HIDDEN, d_hidden_norm])
  draft_load_f32(["norm.weight", HIDDEN, d_norm])
  d_hp_w = draft_proj("candidate_selector.hidden_projection.weight")
  d_pred_cb = draft_tensor("candidate_selector.predecessor_codebook")
  d_succ_cb = draft_tensor("candidate_selector.successor_codebook")
  l = 0
  while l < D_LAYERS
    pre = "layers." + l.to_s + "."
    in_norm = metal_buffer(device, HIDDEN * 4)
    post_norm = metal_buffer(device, HIDDEN * 4)
    qn = metal_buffer(device, D_HD * 4)
    kn = metal_buffer(device, D_HD * 4)
    attn_base = metal_buffer(device, 4 * HIDDEN * 4)
    mlp_base = metal_buffer(device, 4 * HIDDEN * 4)
    draft_load_f32([pre + "input_layernorm.weight", HIDDEN, in_norm])
    draft_load_f32([pre + "post_attention_layernorm.weight", HIDDEN, post_norm])
    draft_load_f32([pre + "self_attn.q_norm.weight", D_HD, qn])
    draft_load_f32([pre + "self_attn.k_norm.weight", D_HD, kn])
    draft_load_f32([pre + "attention_conv.base_kernel", 4 * HIDDEN, attn_base])
    draft_load_f32([pre + "mlp_conv.base_kernel", 4 * HIDDEN, mlp_base])
    dlayers.push({
      in_norm: in_norm, post_norm: post_norm, qn: qn, kn: kn,
      attn_base: attn_base, mlp_base: mlp_base,
      attn_kp: draft_proj(pre + "attention_conv.kernel_projection.weight"),
      mlp_kp: draft_proj(pre + "mlp_conv.kernel_projection.weight"),
      q: draft_proj(pre + "self_attn.q_proj.weight"),
      k: draft_proj(pre + "self_attn.k_proj.weight"),
      v: draft_proj(pre + "self_attn.v_proj.weight"),
      o: draft_proj(pre + "self_attn.o_proj.weight"),
      gate: draft_proj(pre + "mlp.gate_proj.weight"),
      up: draft_proj(pre + "mlp.up_proj.weight"),
      down: draft_proj(pre + "mlp.down_proj.weight"),
      k_cache: metal_buffer(device, MAX_POS * D_KVDIM * 4),
      v_cache: metal_buffer(device, MAX_POS * D_KVDIM * 4)
    })
    l = l + 1
  # Draft scratch (rows = block width <= MULTI_MAX).
  d_x = metal_buffer(device, MULTI_MAX * HIDDEN * 4)
  d_xn = metal_buffer(device, MULTI_MAX * HIDDEN * 4)
  d_xa = metal_buffer(device, MULTI_MAX * HIDDEN * 4)
  d_kp = metal_buffer(device, MULTI_MAX * D_KP * 4)
  d_q = metal_buffer(device, MULTI_MAX * D_QDIM * 4)
  d_k = metal_buffer(device, MULTI_MAX * D_KVDIM * 4)
  d_v = metal_buffer(device, MULTI_MAX * D_KVDIM * 4)
  d_attn = metal_buffer(device, MULTI_MAX * D_QDIM * 4)
  d_ao = metal_buffer(device, MULTI_MAX * HIDDEN * 4)
  d_gate = metal_buffer(device, MULTI_MAX * FFN * 4)
  d_up = metal_buffer(device, MULTI_MAX * FFN * 4)
  d_hid = metal_buffer(device, MULTI_MAX * FFN * 4)
  d_mo = metal_buffer(device, MULTI_MAX * HIDDEN * 4)
  d_hf = metal_buffer(device, MULTI_MAX * HIDDEN * 4)
  d_hp = metal_buffer(device, MULTI_MAX * D_RANK * 4)
  d_cand = metal_buffer(device, MULTI_MAX * D_TOPK * 4)
  d_unary = metal_buffer(device, MULTI_MAX * D_TOPK * 4)
  d_draft_out = metal_buffer(device, MULTI_MAX * 4)
  d_cos = metal_buffer(device, MULTI_MAX * D_ROT_HALF * 4)
  d_sin = metal_buffer(device, MULTI_MAX * D_ROT_HALF * 4)
  d_ccos = metal_buffer(device, MULTI_MAX * D_ROT_HALF * 4)
  d_csin = metal_buffer(device, MULTI_MAX * D_ROT_HALF * 4)
  d_ctx_in = metal_buffer(device, MULTI_MAX * D_CTX_DIM * 4)
  d_ctx_proj = metal_buffer(device, MULTI_MAX * HIDDEN * 4)
  d_ctx_n = metal_buffer(device, MULTI_MAX * HIDDEN * 4)
  d_ck = metal_buffer(device, MULTI_MAX * D_KVDIM * 4)
  d_cv = metal_buffer(device, MULTI_MAX * D_KVDIM * 4)

# [w, input, output, kdim, rows, n]: route to the bf16 wide kernel or the
# NVFP4 width-n rung the verify uses.
-> enqueue_draft_mm(spec)
  if draft_quant
    enqueue_scaled_multi(spec)
  else
    enqueue_bf16_multi(spec)

# Widen a bf16 tensor into an f32 buffer (plain, no +1 shift: the drafter's
# norms are standard HF RMSNorm weights).
-> draft_load_f32(spec)
  name = spec[0]
  n = spec[1]
  out = spec[2]
  t = dst.tensor(name)
  m = dst.mmap
  i = 0
  while i < n
    off = t[:byte_offset] + i * 2
    bits = m.byte_at(off) | (m.byte_at(off + 1) << 8)
    metal_buffer_write_i32(out, i, bits << 16)
    i = i + 1

-> build_rope_draft(spec)
  cosb = spec[0]
  sinb = spec[1]
  pos_start = spec[2]
  n = spec[3]
  token = 0
  while token < n
    i = 0
    while i < D_ROT_HALF
      theta = Math.exp(d_log_rope * (~0.0 - i * d_rope_power))
      angle = (pos_start + token) * theta
      metal_buffer_write_f32(cosb, token * D_ROT_HALF + i, Math.cos(angle))
      metal_buffer_write_f32(sinb, token * D_ROT_HALF + i, Math.sin(angle))
      i = i + 1
    token = token + 1

# [w, input, output, kdim, rows, n]  (bf16 weight [rows, kdim], f32 rows)
-> enqueue_bf16_multi(spec)
  metal_dispatch_groups(queue, bf16_wide_r2_pipe,
    [spec[0], spec[1], spec[2], spec[3], spec[4], spec[5]], (spec[4] + 3) / 4, 64)

# Feed committed positions [start, start + count) to the drafter's context:
# fc over the five taps, hidden_norm, then per layer the K/V projections,
# k_norm + RoPE at the row's absolute position, appended to the draft cache.
# Chunks of DRAFT_MAX rows; nothing attends here, so chunk order is free.
-> dflash2_ingest(start, count)
  profile_t0 = profile_components ? ccall("__w_clock_ms") : ~0.0
  # The bf16 wide kernel hoists at most 8 rows; the NVFP4 drafter rides the
  # GEMM rungs and can take MULTI_MAX rows per chunk.
  chunk_cap = draft_quant ? MULTI_MAX : 8
  done = 0
  while done < count
    m = count - done
    if m > chunk_cap then m = chunk_cap
    row = start + done
    build_rope_draft([d_ccos, d_csin, row, m])
    metal_batch_begin_concurrent(queue)
    metal_dispatch_n(queue, copy_f32_at_pipe,
      [ctx_hidden, d_ctx_in, row * D_CTX_DIM, 0, m * D_CTX_DIM], m * D_CTX_DIM)
    dependency_barrier()
    enqueue_draft_mm([d_fc, d_ctx_in, d_ctx_proj, D_CTX_DIM, HIDDEN, m])
    dependency_barrier()
    enqueue_rms([d_ctx_proj, d_hidden_norm, d_ctx_n, m])
    dependency_barrier()
    l = 0
    while l < D_LAYERS
      dl = dlayers[l]
      enqueue_draft_mm([dl[:k], d_ctx_n, d_ck, HIDDEN, D_KVDIM, m])
      enqueue_draft_mm([dl[:v], d_ctx_n, d_cv, HIDDEN, D_KVDIM, m])
      dependency_barrier()
      metal_dispatch_groups(queue, phn_rope_multi_pipe,
        [d_ck, dl[:kn], d_ccos, d_csin, D_HD, D_ROT_HALF, D_KV, ~1.0 / D_HD, EPS, m], m * D_KV, 32)
      dependency_barrier()
      metal_dispatch_n(queue, kv_write_multi_pipe,
        [d_ck, d_cv, dl[:k_cache], dl[:v_cache], row, D_KVDIM, m], m * D_KVDIM)
      dependency_barrier()
      l = l + 1
    metal_batch_commit(queue)
    done = done + m
  if profile_components
    profile_stats[9] = profile_stats[9] + ccall("__w_clock_ms") - profile_t0
    profile_stats[10] = profile_stats[10] + count

# One block-diffusion pass: token_multi_buf holds [anchor, MASK x (n-1)] at
# positions anchor_pos .. anchor_pos+n-1; the context cache holds every
# position < anchor_pos. Writes the selected draft ids into
# token_multi_buf[1..n-1] (the verify embeds straight from it) and
# d_draft_out[0..n-2]. Committed async; returns the command-buffer handle.
-> dflash2_draft(anchor_pos, n)
  profile_t0 = profile_components ? ccall("__w_clock_ms") : ~0.0
  build_rope_draft([d_cos, d_sin, anchor_pos, n])
  metal_batch_begin_concurrent(queue)
  metal_dispatch_n(queue, multi_embed_pipe,
    [embed_w, d_x, token_multi_buf, HIDDEN, n], n * HIDDEN)
  dependency_barrier()
  l = 0
  while l < D_LAYERS
    dl = dlayers[l]
    enqueue_rms([d_x, dl[:in_norm], d_xn, n])
    dependency_barrier()
    enqueue_draft_mm([dl[:attn_kp], d_xn, d_kp, HIDDEN, D_KP, n])
    dependency_barrier()
    metal_dispatch_n(queue, dyn_conv_pipe,
      [d_xn, d_kp, dl[:attn_base], d_xa, 0, HIDDEN, n], n * HIDDEN)
    dependency_barrier()
    enqueue_draft_mm([dl[:q], d_xa, d_q, HIDDEN, D_QDIM, n])
    enqueue_draft_mm([dl[:k], d_xa, d_k, HIDDEN, D_KVDIM, n])
    enqueue_draft_mm([dl[:v], d_xa, d_v, HIDDEN, D_KVDIM, n])
    dependency_barrier()
    metal_dispatch_groups(queue, phn_rope_multi_pipe,
      [d_q, dl[:qn], d_cos, d_sin, D_HD, D_ROT_HALF, D_HEADS, ~1.0 / D_HD, EPS, n], n * D_HEADS, 32)
    metal_dispatch_groups(queue, phn_rope_multi_pipe,
      [d_k, dl[:kn], d_cos, d_sin, D_HD, D_ROT_HALF, D_KV, ~1.0 / D_HD, EPS, n], n * D_KV, 32)
    dependency_barrier()
    metal_dispatch_groups(queue, sdpa_draft_pipe,
      [d_q, dl[:k_cache], dl[:v_cache], d_k, d_v, d_attn,
       D_HEADS, D_KV, anchor_pos, n, D_WINDOW, D_SCALE], n * D_HEADS, 128)
    dependency_barrier()
    enqueue_draft_mm([dl[:o], d_attn, d_ao, D_QDIM, HIDDEN, n])
    dependency_barrier()
    metal_dispatch_n(queue, dyn_conv_res_pipe,
      [d_ao, d_kp, dl[:attn_base], d_x, 1, HIDDEN, n], n * HIDDEN)
    dependency_barrier()
    enqueue_rms([d_x, dl[:post_norm], d_xn, n])
    dependency_barrier()
    enqueue_draft_mm([dl[:mlp_kp], d_xn, d_kp, HIDDEN, D_KP, n])
    dependency_barrier()
    metal_dispatch_n(queue, dyn_conv_pipe,
      [d_xn, d_kp, dl[:mlp_base], d_xa, 0, HIDDEN, n], n * HIDDEN)
    dependency_barrier()
    enqueue_draft_mm([dl[:gate], d_xa, d_gate, HIDDEN, FFN, n])
    enqueue_draft_mm([dl[:up], d_xa, d_up, HIDDEN, FFN, n])
    dependency_barrier()
    metal_dispatch_n(queue, silu_pipe, [d_gate, d_up, d_hid, n * FFN], n * FFN)
    dependency_barrier()
    enqueue_draft_mm([dl[:down], d_hid, d_mo, FFN, HIDDEN, n])
    dependency_barrier()
    metal_dispatch_n(queue, dyn_conv_res_pipe,
      [d_mo, d_kp, dl[:mlp_base], d_x, 1, HIDDEN, n], n * HIDDEN)
    dependency_barrier()
    l = l + 1
  enqueue_rms([d_x, d_norm, d_hf, n])
  dependency_barrier()
  enqueue_scaled_multi([lm_head, d_hf, logits_multi, HIDDEN, N_VOCAB, n])
  enqueue_draft_mm([d_hp_w, d_hf, d_hp, HIDDEN, D_RANK, n])
  dependency_barrier()
  metal_dispatch_groups(queue, topk_pipe,
    [logits_multi, d_cand, d_unary, N_VOCAB, 1], n - 1, 256)
  dependency_barrier()
  metal_dispatch_groups(queue, selector_pipe,
    [d_hp, d_pred_cb, d_succ_cb, d_cand, d_unary, token_multi_buf, d_draft_out, n], 1, 256)
  cb = metal_batch_commit_async(queue)
  if profile_components
    profile_stats[7] = profile_stats[7] + ccall("__w_clock_ms") - profile_t0
    profile_stats[8] = profile_stats[8] + 1
  cb

-> forward(token_id, pos, want_logits)
  profile_t0 = profile_components ? ccall("__w_clock_ms") : ~0.0
  if pos > 0 then build_rope(pos)
  if concurrent then metal_batch_begin_concurrent(queue) else metal_batch_begin(queue)
  metal_dispatch_n(queue, bf16_embed_pipe, [embed_w, x, token_id, HIDDEN], HIDDEN)
  dependency_barrier()
  if !optimized then metal_batch_commit(queue)

  li = 0
  while li < N_LAYERS
    if !optimized then metal_batch_begin(queue)
    lyr = layers[li]
    if lyr[:kind] == "mamba" then enqueue_mamba(lyr) else enqueue_full(lyr, pos)
    enqueue_ffn(lyr)
    if tap_capture
      # enqueue_ffn ends on a barrier, so x is the finished layer output here;
      # the copy is a read, and the next layer only writes x after further
      # barriers, so no extra barrier is needed after it.
      t = 0
      while t < 5
        if tap_layers[t] == li
          metal_dispatch_n(queue, copy_f32_at_pipe,
            [x, tap_buf, 0, (pos * 5 + t) * HIDDEN, HIDDEN], HIDDEN)
        t = t + 1
    if !optimized then metal_batch_commit(queue)
    li = li + 1

  if !optimized then metal_batch_begin(queue)
  if want_logits || mtp_enabled
    enqueue_rms([x, final_norm, xn, 1])
    dependency_barrier()
    if mtp_enabled
      # PRE-final-norm hidden. The MTP head's own pre_fc_norm_hidden IS the
      # normalization step, so it expects the raw backbone output; feeding it
      # xn double-normalizes -- normalize(x * final_norm) * mtp_hnorm instead
      # of normalize(x) * mtp_hnorm. That leaves every emitted token correct,
      # because the target decides all of them, and silently costs acceptance.
      metal_dispatch_n(queue, copy_pipe, [x, backbone_hidden, 0, HIDDEN], HIDDEN)
      dependency_barrier()
  if want_logits
    enqueue_scaled([lm_head, xn, logits, HIDDEN, N_VOCAB])
    dependency_barrier()
    enqueue_argmax([logits, argmax_out, 1])
  metal_batch_commit(queue)
  result = want_logits ? metal_buffer_read_i32(argmax_out, 0) : -1
  if profile_components
    profile_dt = ccall("__w_clock_ms") - profile_t0
    if profile_stats[0] == 1
      profile_stats[3] = profile_stats[3] + profile_dt
      if profile_stats[4] == 0
        profile_stats[15] = profile_dt
      else
        profile_stats[16] = profile_stats[16] + profile_dt
      profile_stats[4] = profile_stats[4] + 1
    else
      profile_stats[1] = profile_stats[1] + profile_dt
      profile_stats[2] = profile_stats[2] + 1
  result

# The raw Ollama prompt tokenization is stable for this tokenizer. The 5-token
# form is the parity fixture ("The capital of France is" -> 11751) and is left
# exactly as it was.
prompt_seed = [760, 6511, 314, 9338, 369]

# LONGER PROMPTS USE REAL PROSE, NOT A TILED SEED.
#
# Tiling a 5-token seed produces a period-5 sequence whose continuation is
# trivially predictable, so the MTP head accepts essentially every draft
# (the 12/12 and 24/24 acceptance in the model README). That is a saturated
# regime, and a saturated fixture cannot discriminate ANY draft-schedule
# change: at accept ~= 1.0 every depth looks good and the marginal cost of a
# rejected draft never appears. Measurements of MTP depth policy, the
# mtp-auto controller, and the MTP-1-vs-MTP-2 comparison are all decided by
# the acceptance regime, so they need material that actually rejects.
#
# Ordinary English prose continuation lands near accept 0.65-0.85, which is
# the band where those decisions have a sign. Encoding real text costs one
# tokenizer load and changes nothing about the compute graph.
prompt_prose = "The naturalist spent the better part of three seasons observing the colony, recording each departure and return in a leather notebook that gradually lost its shape to the damp. What struck him was not the industry of the birds, which every account had prepared him for, but the intervals of apparent idleness between flights, and how unevenly those intervals were distributed across the season. He began to suspect that the pattern he had come to describe was less a property of the animals than of the hours he had chosen to watch them. His notebooks from the second season are the ones worth reading. He had abandoned the ruled columns by then and written in continuous prose, which made the entries longer and far less useful as data, but it is in those pages that the shift in his thinking is visible. He stops counting birds and starts counting silences. A departure is easy to see and simple to record; an absence has no edge to it, and deciding when one has begun requires a judgement the observer must make and cannot check. He worried about this at length. There is an entry in late June in which he lists four different definitions of idleness and then crosses out all of them, and beneath the deletions he has written that the difficulty is not in the birds. The third season he brought a second observer, a young woman from the mainland whose name appears only as initials. Their records disagree constantly, and he treats every disagreement as a finding rather than an error, which was unusual for the period. Where she saw a colony at rest he saw a colony waiting, and he could not persuade her that the distinction meant anything, nor could she persuade him that it did not. The argument runs through the margins of both notebooks for eleven weeks. It is never settled. What ends it is the weather: a storm in September took the shelter and most of the season's later pages, and when he returned the following spring he did not resume the study. The manuscript that survives was assembled thirty years afterward by an editor who never met him and who arranged the entries by date rather than by subject, which scatters the argument badly. Read in that order the work looks like a failure, an inventory that was never completed. Read the other way, following the questions instead of the calendar, it is something more interesting: a careful account of a man discovering that his instrument was himself, and that the thing he had set out to measure did not exist independently of the schedule he had chosen for measuring it. He seems to have understood this before he had a vocabulary for it. The last legible entry, written in a hand much worse than the rest, observes that the birds keep no hours at all and that the seasons he had been describing were his own."
prompt_prose_tech = "A cache is a small, fast store that holds copies of data from a larger and slower store. When the processor needs a value it first checks the cache. If the value is present, the access is called a hit and completes in a few cycles. If it is not present, the access is a miss and the processor must fetch the value from main memory, which takes far longer. The fraction of accesses that hit is the hit rate, and because the cost of a miss is so much higher than the cost of a hit, even a small change in the hit rate can dominate the average access time. Caches work because programs do not access memory at random. They exhibit locality. Temporal locality means that a value accessed once is likely to be accessed again soon, so it is worth keeping. Spatial locality means that if a value is accessed, nearby values are likely to be accessed soon as well, so it is worth fetching a whole block rather than a single word. Both effects are properties of the way people write programs rather than properties of the hardware, which is why cache design is ultimately an empirical discipline. A cache is organized into lines, each holding a fixed number of bytes. The mapping from an address to a line determines the organization. In a direct mapped cache each address maps to exactly one line, which makes lookup cheap but means two addresses that map to the same line will evict each other repeatedly even when the rest of the cache is empty. A fully associative cache allows any address in any line, which removes that problem but makes lookup expensive because every line must be checked. Set associative caches sit between the two: the cache is divided into sets, an address maps to one set, and within that set any line may be used. Most processors use set associative caches with a small number of ways. When a new block must be brought in and the set is full, the cache must choose a line to evict. The replacement policy makes that choice. Least recently used is the common choice because it exploits temporal locality directly, but tracking exact usage order is expensive for large sets, so real implementations approximate it. Writes require a further decision. A write through cache updates memory on every write, which keeps memory consistent but generates a great deal of traffic. A write back cache updates only the cache line and marks it dirty, writing to memory only when the line is evicted. Write back is usually faster and is what most designs use."

prompt = []
i = 0
if profile_prompt_tokens <= prompt_seed.size()
  while i < profile_prompt_tokens
    prompt.push(prompt_seed[i % prompt_seed.size()])
    i = i + 1
else
  prompt_tokenizer = Tungsten:Llama:Tokenizer.from_packed_tokenizer(TOKENIZER_BIN)
  prose_source = prose_tech ? prompt_prose_tech : prompt_prose
  prose_ids = prompt_tokenizer.encode(prose_source)
  if prose_ids.size() < 1 then raise "prose prompt tokenized to nothing"
  while i < profile_prompt_tokens
    # Tiling a passage makes it periodic, and a periodic prompt is a SATURATED
    # fixture: the head accepts nearly everything and no schedule decision has a
    # sign. Say so rather than reporting a number that looks fine.
    if i >= prose_ids.size() && i == prose_ids.size()
      << "WARNING: prose fixture exhausted at " + prose_ids.size().to_s + " tokens; prompt is now TILED and acceptance is not trustworthy"
    prompt.push(prose_ids[i % prose_ids.size()])
    i = i + 1
if prompt_ids_file != ""
  prompt = JSON.parse(read_file(prompt_ids_file))
  if prompt.size() + n_generate > MAX_POS
    raise "prompt file " + prompt.size().to_s + " + generate " + n_generate.to_s + " exceeds MAX_POS " + MAX_POS.to_s
  if prefill_gemm && prompt.size() + n_generate > SDPA_MULTI_MAX_POS
    raise "prompt file " + prompt.size().to_s + " + generate " + n_generate.to_s + " exceeds the block-verify SDPA ceiling " + SDPA_MULTI_MAX_POS.to_s + "; attention would silently truncate"
setup_elapsed = ccall("__w_clock_ms") - setup_t0
<< "prefill " + prompt.size().to_s + " tokens"
prefill_t0 = ccall("__w_clock_ms")
profile_stats[0] = 1
g_na_ffn = prefill_gemm && ccall("__w_env", "M4_FFN") != "0"
# The attention/GDN projections (q, k, v, o and qkv, z, out) on the Neural
# Accelerators. Chunks wider than the 64-row simdgroup ladder go there
# regardless -- this toggle is what makes the FFN-only arm measurable at
# chunk 64.
g_na_attn = prefill_gemm && ccall("__w_env", "NA_ATTN") != "0"
i = 0
pred = -1
prefill_last_batched = false
while i < prompt.size()
  if prefill_gemm && prompt.size() - i >= 2
    m = prompt.size() - i
    if m > MULTI_MAX then m = MULTI_MAX
    chunk = []
    j = 0
    while j < m
      chunk.push(prompt[i + j])
      j = j + 1
    is_last = i + m == prompt.size()
    preds = forward_multi([chunk, i, m, tap_capture, is_last ? "last" : "none"])
    if is_last then pred = preds[0]
    if mtp_enabled
      j = 0
      while j < m && i + j + 1 < prompt.size()
        mtp_step([prompt[i + j + 1], backbone_hidden, i + j, false, [x_multi, j]])
        j = j + 1
      if is_last then copy_hidden_multi_row(m - 1)
    prefill_last_batched = false
    if profile_components
      profile_stats[4] = profile_stats[4] + m
    i = i + m
  elsif devchain && prompt.size() - i >= 3
    # 3-token backbone chunk (one weight stream), then per-token head
    # appends staged from x_triplet. Head priming is preserved, so decode
    # acceptance is unchanged; ids are bit-identical to serial prefill.
    pred = forward_prefill_chunk(
      [prompt[i], prompt[i + 1], prompt[i + 2], i,
       i + 3 == prompt.size()])
    if mtp_enabled
      j = 0
      while j < 3 && i + j + 1 < prompt.size()
        mtp_step([prompt[i + j + 1], backbone_hidden, i + j, false, [x_triplet, j]])
        j = j + 1
    prefill_last_batched = true
    i = i + 3
  else
    pred = forward(prompt[i], i, i == prompt.size() - 1)
    if mtp_enabled && i + 1 < prompt.size()
      mtp_step([prompt[i + 1], backbone_hidden, i, false])
    prefill_last_batched = false
    i = i + 1
# The head appends clobber backbone_hidden with staged rows; restore it to
# the last prompt token's hidden for the first decode draft.
if prefill_last_batched && mtp_enabled
  copy_hidden_triplet_row(2)
g_na_ffn = false
g_na_attn = false
profile_stats[0] = 0
prefill_elapsed = ccall("__w_clock_ms") - prefill_t0
if prompt.size() == 5 && pred != 11751
  raise "Qwen3.8 parity failure: expected first token 11751, got " + pred.to_s
if prompt.size() == 5 then << "parity PASS: first token 11751 ( Paris)"

ids = []
ids.push(pred)
pos = prompt.size()
t0 = ccall("__w_clock_ms")
accepted = 0
drafted = 0
deep_drafted = 0
deep_accepted = 0
# Adaptive arm state: completed rounds, emitted tokens, and elapsed ms for
# depth 1 and depth 2. Arrays keep updates visible across the decode loop.
mtp_auto_rounds = [0, 0]
mtp_auto_tokens = [0, 0]
mtp_auto_ms = [~0.0, ~0.0]
# Per-round timing. Total wall clock is a poor instrument on a contended box
# -- a single descheduled round drags the whole run -- whereas the MEDIAN
# round rejects those outliers and is what actually changed when a kernel
# gets faster. Reported alongside tok/s so a regression can be told apart
# from the room. Defined for every mode: the summary below reads it, and in
# the compiled front-end an undefined name is a nil deref (SIGSEGV), not a
# runtime error -- serial modes crashed right after prefill with no output.
round_ms = []
if mtp_enabled
  current = pred
  draft = mtp_step([current, backbone_hidden, pos - 1])
  generated = 0
  # Streak-gated depth, ported from the MLX board's segmented verify gate: only
  # spend the deeper schedule on stretches where the head is ALREADY proving
  # perfect, and reset on any reject. Depth 3 measured +3.1% on expository prose
  # (4/4 paired) and -13% on literary, because the literary chain decays too
  # fast to fill the fourth row -- a fixed depth has to pick one of those. The
  # gate is conditioned on observed acceptance, so it cannot touch a cold or
  # hard stretch at all; it only shortens the re-qualification ramp.
  full_accept_streak = 0
  while generated < n_generate
    rt0 = ccall("__w_clock_ms")
    remaining = n_generate - generated
    if remaining == 1
      current = forward(current, pos, true)
      ids.push(current)
      pos = pos + 1
      generated = generated + 1
    else
      use_depth3 = mtp_depth3 && remaining >= 4 && full_accept_streak >= 2
      use_depth2 = mtp_depth2 && remaining >= 3
      if mtp_adaptive && remaining >= 3
        if mtp_auto_rounds[0] == 0
          use_depth2 = false
        else
          if mtp_auto_rounds[1] == 0
            use_depth2 = true
          else
            depth1_score = (~0.0 + mtp_auto_tokens[0]) / mtp_auto_ms[0]
            depth2_score = (~0.0 + mtp_auto_tokens[1]) / mtp_auto_ms[1]
            use_depth2 = depth2_score > depth1_score
      arm = use_depth2 ? 1 : 0
      round_generated_before = generated
      round_t0 = mtp_adaptive ? ccall("__w_clock_ms") : ~0.0
      if use_depth3
        # Three drafts, four verified rows. Same causal-chain shape as depth 2:
        # each draft is the head's own continuation of the previous one, and the
        # target's row k decides draft k.
        verify_draft0 = draft
        if devchain
          # Two-step device-resident chain: draft1 argmax -> token slot 2,
          # draft2 reads slot 2 as its input and writes slot 3, both async.
          # One GPU sync (the verify) instead of three.
          cb1 = mtp_step([verify_draft0, xn, pos, true, nil, [token_quad_buf, 2]])
          cb2 = mtp_step([0, xn, pos + 1, true, nil, [token_quad_buf, 3], [token_quad_buf, 2]])
          quad_preds = forward_quad(
            [current, verify_draft0, 0, 0, pos, true])
          metal_command_buffer_wait(cb1)
          metal_command_buffer_wait(cb2)
          verify_draft1 = metal_buffer_read_i32(token_quad_buf, 2)
          verify_draft2 = metal_buffer_read_i32(token_quad_buf, 3)
        else
          verify_draft1 = mtp_step([verify_draft0, xn, pos])
          verify_draft2 = mtp_step([verify_draft1, xn, pos + 1])
          if force_reject && drafted == 0
            verify_draft0 = (verify_draft0 + 1) % N_VOCAB
          if multi_verify
            quad_preds = forward_multi(
              [[current, verify_draft0, verify_draft1, verify_draft2], pos, 4])
          else
            quad_preds = forward_quad(
              [current, verify_draft0, verify_draft1, verify_draft2, pos])
        accepted_now = 0
        if quad_preds[0] == verify_draft0
          accepted_now = 1
          if quad_preds[1] == verify_draft1
            accepted_now = 2
            if quad_preds[2] == verify_draft2
              accepted_now = 3
        accepted = accepted + accepted_now
        drafted = drafted + 3
        deep_drafted = deep_drafted + 1
        if accepted_now == 3 then deep_accepted = deep_accepted + 1
        if accepted_now == 3
          full_accept_streak = full_accept_streak + 1
        else
          full_accept_streak = 0
        if accepted_now == 3
          ids.push(verify_draft0)
          ids.push(verify_draft1)
          ids.push(verify_draft2)
          bonus = quad_preds[3]
          ids.push(bonus)
          generated = generated + 4
          if generated < n_generate
            mtp_step([verify_draft0, backbone_hidden, pos, false, [x_verify4, 0]])
            mtp_step([verify_draft1, backbone_hidden, pos + 1, false, [x_verify4, 1]])
            mtp_step([verify_draft2, backbone_hidden, pos + 2, false, [x_verify4, 2]])
            draft = mtp_step([bonus, backbone_hidden, pos + 3, true, [x_verify4, 3]])
          current = bonus
          pos = pos + 4
        else
          if multi_verify then rollback_multi_states(accepted_now, 4) else rollback_quad_states(accepted_now)
          if accepted_now == 2
            ids.push(verify_draft0)
            ids.push(verify_draft1)
            correction = quad_preds[2]
            ids.push(correction)
            generated = generated + 3
            if generated < n_generate
              mtp_step([verify_draft0, backbone_hidden, pos, false, [x_verify4, 0]])
              mtp_step([verify_draft1, backbone_hidden, pos + 1, false, [x_verify4, 1]])
              draft = mtp_step([correction, backbone_hidden, pos + 2, true, [x_verify4, 2]])
            current = correction
            pos = pos + 3
          elsif accepted_now == 1
            ids.push(verify_draft0)
            correction = quad_preds[1]
            ids.push(correction)
            generated = generated + 2
            if generated < n_generate
              mtp_step([verify_draft0, backbone_hidden, pos, false, [x_verify4, 0]])
              draft = mtp_step([correction, backbone_hidden, pos + 1, true, [x_verify4, 1]])
            current = correction
            pos = pos + 2
          else
            correction = quad_preds[0]
            ids.push(correction)
            generated = generated + 1
            if generated < n_generate
              draft = mtp_step([correction, backbone_hidden, pos, true, [x_verify4, 0]])
            current = correction
            pos = pos + 1
      elsif use_depth2
        verify_draft0 = draft
        if devchain
          # Chained draft argmax stays on device; copy_i32_at drops it into
          # the verify token slot, one async commit. Read it back only after
          # the verify -- one GPU sync this round instead of two.
          draft_cb = mtp_step([verify_draft0, xn, pos, true, nil, [token_triplet_buf, 2]])
          triplet_preds = forward_triplet(
            [current, verify_draft0, 0, pos, true])
          metal_command_buffer_wait(draft_cb)
          verify_draft1 = metal_buffer_read_i32(argmax_out, 0)
        else
          verify_draft1 = mtp_step([verify_draft0, xn, pos])
          if force_reject && drafted == 0
            verify_draft0 = (verify_draft0 + 1) % N_VOCAB
          if multi_verify
            triplet_preds = forward_multi(
              [[current, verify_draft0, verify_draft1], pos, 3])
          else
            triplet_preds = forward_triplet(
              [current, verify_draft0, verify_draft1, pos])
        accepted_now = 0
        if triplet_preds[0] == verify_draft0
          accepted_now = 1
          if triplet_preds[1] == verify_draft1
            accepted_now = 2
        accepted = accepted + accepted_now
        drafted = drafted + 2
        deep_drafted = deep_drafted + 1
        if accepted_now == 2 then deep_accepted = deep_accepted + 1
        if accepted_now == 2
          full_accept_streak = full_accept_streak + 1
        else
          full_accept_streak = 0
        if accepted_now == 2
          ids.push(verify_draft0)
          ids.push(verify_draft1)
          bonus = triplet_preds[2]
          ids.push(bonus)
          generated = generated + 3
          if generated < n_generate
            mtp_step([verify_draft0, backbone_hidden, pos, false, [x_verify3, 0]])
            mtp_step([verify_draft1, backbone_hidden, pos + 1, false, [x_verify3, 1]])
            draft = mtp_step([bonus, backbone_hidden, pos + 2, true, [x_verify3, 2]])
          current = bonus
          pos = pos + 3
        else
          if multi_verify then rollback_multi_states(accepted_now, 3) else rollback_triplet_states(accepted_now)
          if accepted_now == 1
            ids.push(verify_draft0)
            correction = triplet_preds[1]
            ids.push(correction)
            generated = generated + 2
            if generated < n_generate
              mtp_step([verify_draft0, backbone_hidden, pos, false, [x_verify3, 0]])
              draft = mtp_step([correction, backbone_hidden, pos + 1, true, [x_verify3, 1]])
            current = correction
            pos = pos + 2
          else
            correction = triplet_preds[0]
            ids.push(correction)
            generated = generated + 1
            if generated < n_generate
              draft = mtp_step([correction, backbone_hidden, pos, true, [x_verify3, 0]])
            current = correction
            pos = pos + 1
      else
        verify_draft = draft
        if force_reject && drafted == 0
          verify_draft = (draft + 1) % N_VOCAB
        pair_preds = forward_pair([current, verify_draft, pos])
        drafted = drafted + 1
        if draft_rank_probe && !full_draft_vocab
          probe_rank = draft_target_rank(pair_preds[0])
          rank_samples = rank_samples + 1
          if probe_rank < 0
            rank_outside = rank_outside + 1
          else
            probe_slot = probe_rank < 5 ? probe_rank : 5
            rank_hist[probe_slot] = rank_hist[probe_slot] + 1
        if pair_preds[0] == verify_draft
          full_accept_streak = full_accept_streak + 1
          accepted = accepted + 1
          ids.push(verify_draft)
          bonus = pair_preds[1]
          ids.push(bonus)
          generated = generated + 2
          if generated < n_generate
            mtp_step([verify_draft, backbone_hidden, pos, false, [x_pair, 0]])
            draft = mtp_step([bonus, backbone_hidden, pos + 1, true, [x_pair, 1]])
          current = bonus
          pos = pos + 2
        else
          full_accept_streak = 0
          rollback_pair_states()
          current = pair_preds[0]
          ids.push(current)
          generated = generated + 1
          if generated < n_generate
            draft = mtp_step([current, backbone_hidden, pos, true, [x_pair, 0]])
          pos = pos + 1
      if mtp_adaptive
        mtp_auto_rounds[arm] = mtp_auto_rounds[arm] + 1
        mtp_auto_tokens[arm] = mtp_auto_tokens[arm] + generated - round_generated_before
        mtp_auto_ms[arm] = mtp_auto_ms[arm] + ccall("__w_clock_ms") - round_t0
    while hist_cb_n[0] > 0
      hist_cb_n[0] = hist_cb_n[0] - 1
      metal_command_buffer_wait(hist_cbs[hist_cb_n[0]])
    round_ms.push(ccall("__w_clock_ms") - rt0)
elsif dflash2_enabled
  # Block rounds: ingest the taps of every position < anchor into the draft
  # context, draft [anchor, MASK...] in one pass, verify the block with the
  # width-n exact target pass (one host sync per round), commit the longest
  # matching prefix plus the target's own next token, replay the recurrent
  # state to the commit point, and continue from that token.
  ctx_done = 0
  anchor = pred
  anchor_pos = prompt.size()
  generated = 0
  dflash2_rounds = 0
  while generated < n_generate
    rt0 = ccall("__w_clock_ms")
    remaining = n_generate - generated
    n = remaining < dflash2_block ? remaining : dflash2_block
    if n < 2
      preds = forward_multi([[anchor], anchor_pos, 1])
      ids.push(preds[0])
      generated = generated + 1
      anchor = preds[0]
      anchor_pos = anchor_pos + 1
    else
      if ctx_done < anchor_pos
        dflash2_ingest(ctx_done, anchor_pos - ctx_done)
        ctx_done = anchor_pos
      metal_buffer_write_i32(token_multi_buf, 0, anchor)
      j = 1
      while j < n
        metal_buffer_write_i32(token_multi_buf, j, D_MASK)
        j = j + 1
      draft_cb = dflash2_draft(anchor_pos, n)
      preds = forward_multi([nil, anchor_pos, n, true])
      metal_command_buffer_wait(draft_cb)
      accepted_now = 0
      while accepted_now < n - 1 && preds[accepted_now] == metal_buffer_read_i32(d_draft_out, accepted_now)
        accepted_now = accepted_now + 1
      if dflash2_rounds == 0
        dbg = []
        j = 0
        while j < n - 1
          dbg.push(metal_buffer_read_i32(d_draft_out, j))
          j = j + 1
        << "dflash2 round 0: anchor " + anchor.to_s + " drafts " + dbg.to_s + " target " + preds.to_s
        if dflash2_probe != ""
          File.write_bytes(dflash2_probe + ".hf.f32", metal_buffer_view(d_hf, 8, n * HIDDEN * 4))
          File.write_bytes(dflash2_probe + ".cand.i32", metal_buffer_view(d_cand, 8, n * D_TOPK * 4))
          File.write_bytes(dflash2_probe + ".unary.f32", metal_buffer_view(d_unary, 8, n * D_TOPK * 4))
          File.write_bytes(dflash2_probe + ".hp.f32", metal_buffer_view(d_hp, 8, n * D_RANK * 4))
          File.write_bytes(dflash2_probe + ".ctxn.f32", metal_buffer_view(d_ctx_n, 8, MULTI_MAX * HIDDEN * 4))
          File.write(dflash2_probe + ".json", "{\"n\": " + n.to_s + ", \"anchor\": " + anchor.to_s + ", \"anchor_pos\": " + anchor_pos.to_s + ", \"drafts\": " + dbg.to_s + ", \"target\": " + preds.to_s + "}")
      j = 0
      while j < accepted_now
        ids.push(metal_buffer_read_i32(d_draft_out, j))
        j = j + 1
      ids.push(preds[accepted_now])
      generated = generated + accepted_now + 1
      drafted = drafted + n - 1
      accepted = accepted + accepted_now
      rollback_multi_states(accepted_now, n)
      anchor = preds[accepted_now]
      anchor_pos = anchor_pos + accepted_now + 1
      dflash2_rounds = dflash2_rounds + 1
    round_ms.push(ccall("__w_clock_ms") - rt0)
  pos = anchor_pos
else
  i = 0
  while i < n_generate
    next_id = forward(ids[ids.size() - 1], pos, true)
    ids.push(next_id)
    pos = pos + 1
    i = i + 1
elapsed = ccall("__w_clock_ms") - t0
tokens_per_second = (~0.0 + n_generate) * 1000.0 / elapsed
if round_ms.size() > 0
  sorted_rounds = round_ms.sort()
  << "rounds: " + round_ms.size().to_s + ", median " + sorted_rounds[round_ms.size() / 2].to_s + " ms, min " + sorted_rounds[0].to_s + " ms"

# ROW SCAN: what does one extra verified row actually cost?
#
# The whole speculative-decode economy turns on this number: a draft schedule
# buys expected tokens per round and pays for them in verified rows, so the
# marginal cost of row k is what decides whether any deeper or wider schedule
# can win. Measuring it by comparing whole decode runs does not work -- this
# box drifts more than 30% between runs, which is larger than the effect --
# so the scan interleaves the widths INSIDE one process on an already-warm
# cache, in the same thermal state, and takes the median over repetitions.
# Positions are reused deliberately: the outputs are garbage, the timings are
# not, and no state escapes the scan.
if row_scan
  # Triplet scratch (cs_mid2 and friends) is only allocated under mtp_depth2,
  # so the scan needs a mode that allocates it.
  if !mtp_depth2 then raise "row-scan requires mode mtp2 or mtp-auto (triplet scratch is allocated only there)"
  scan_reps = 40
  scan_pos = prompt.size()
  scan_tok = ids[0]
  scan1 = []
  scan2 = []
  scan3 = []
  scan4 = []
  scan_multi = [[], [], [], [], [], [], [], [], []]
  r = 0
  while r < scan_reps
    if multi_verify
      mw = 1
      while mw <= MULTI_WIDE_MAX
        mtoks = []
        j = 0
        while j < mw
          mtoks.push(scan_tok)
          j = j + 1
        sm = ccall("__w_clock_ms")
        forward_multi([mtoks, scan_pos, mw])
        scan_multi[mw].push(ccall("__w_clock_ms") - sm)
        mw = mw + 1
    s1 = ccall("__w_clock_ms")
    forward(scan_tok, scan_pos, false)
    scan1.push(ccall("__w_clock_ms") - s1)
    s2 = ccall("__w_clock_ms")
    forward_pair([scan_tok, scan_tok, scan_pos])
    scan2.push(ccall("__w_clock_ms") - s2)
    s3 = ccall("__w_clock_ms")
    forward_triplet([scan_tok, scan_tok, scan_tok, scan_pos])
    scan3.push(ccall("__w_clock_ms") - s3)
    if mtp_depth3
      s4 = ccall("__w_clock_ms")
      forward_quad([scan_tok, scan_tok, scan_tok, scan_tok, scan_pos])
      scan4.push(ccall("__w_clock_ms") - s4)
    r = r + 1
  # Localize the cliff: time one mamba layer, one attention layer, and one FFN
  # in isolation at width 2 vs width 3. Each is wrapped in its own batch so the
  # commit is a real sync point and the timing is that stage's alone.
  scan_mamba = -1
  scan_attn = -1
  li = 0
  while li < N_LAYERS
    if layers[li][:kind] == "mamba"
      if scan_mamba < 0 then scan_mamba = li
    else
      if scan_attn < 0 then scan_attn = li
    li = li + 1
  stage_names = ["mamba", "attn", "ffn"]
  stage_pair = [[], [], []]
  stage_trip = [[], [], []]
  r = 0
  while r < scan_reps
    st = 0
    while st < 3
      t = ccall("__w_clock_ms")
      metal_batch_begin_concurrent(queue)
      if st == 0 then enqueue_mamba_pair(layers[scan_mamba])
      if st == 1 then enqueue_full_pair([layers[scan_attn], scan_pos])
      if st == 2 then enqueue_ffn_pair(layers[scan_attn])
      metal_batch_commit(queue)
      stage_pair[st].push(ccall("__w_clock_ms") - t)
      t = ccall("__w_clock_ms")
      metal_batch_begin_concurrent(queue)
      if st == 0 then enqueue_mamba_triplet(layers[scan_mamba])
      if st == 1 then enqueue_full_triplet([layers[scan_attn], scan_pos])
      if st == 2 then enqueue_ffn_triplet(layers[scan_attn])
      metal_batch_commit(queue)
      stage_trip[st].push(ccall("__w_clock_ms") - t)
      st = st + 1
    r = r + 1
  st = 0
  while st < 3
    p2 = stage_pair[st].sort()[scan_reps / 2]
    p3 = stage_trip[st].sort()[scan_reps / 2]
    << "rowscan stage " + stage_names[st] + ": 2row " + p2.to_s + " ms, 3row " + p3.to_s + " ms, delta " + (p3 - p2).to_s
    st = st + 1

  m1 = scan1.sort()[scan_reps / 2]
  m2 = scan2.sort()[scan_reps / 2]
  m3 = scan3.sort()[scan_reps / 2]
  << "rowscan reps=" + scan_reps.to_s + " variant=" + triplet_variant
  << "rowscan 1row median " + m1.to_s + " ms"
  << "rowscan 2row median " + m2.to_s + " ms  (marginal " + (m2 - m1).to_s + ")"
  << "rowscan 3row median " + m3.to_s + " ms  (marginal " + (m3 - m2).to_s + ")"
  if mtp_depth3
    m4 = scan4.sort()[scan_reps / 2]
    << "rowscan 4row median " + m4.to_s + " ms  (marginal " + (m4 - m3).to_s + ")"
  if multi_verify
    prev = ~0.0
    mw = 1
    while mw <= MULTI_WIDE_MAX
      mm = scan_multi[mw].sort()[scan_reps / 2]
      << "rowscan multi " + mw.to_s + "row median " + mm.to_s + " ms  (marginal " + (mm - prev).to_s + ", variant " + multi_variant + ")"
      prev = mm
      mw = mw + 1

tokenizer = Tungsten:Llama:Tokenizer.from_packed_tokenizer(TOKENIZER_BIN)
text_out = tokenizer.decode(ids)
<< "generated ids: " + ids.to_s
<< "generated: " + text_out
if tapdump
  # Positions 0..P-1 are the prompt, P..P+N-2 the generated tokens that were
  # forwarded (the last generated id is emitted but never consumed).
  tap_positions = prompt.size() + n_generate - 1
  # write_file takes a bytes array or a string, so view the f32 table as u8.
  tap_view = metal_buffer_view(tap_buf, 8, tap_positions * 5 * HIDDEN * 4)
  File.write_bytes(tapdump_prefix + ".f32", tap_view)
  File.write(tapdump_prefix + ".json",
    "{\"prompt\": " + prompt.to_s + ", \"generated\": " + ids.to_s +
    ", \"n_pos\": " + tap_positions.to_s + ", \"taps\": " + tap_layers.to_s + ", \"hidden\": " + HIDDEN.to_s + "}")
  << "tapdump: " + tap_positions.to_s + " positions x 5 taps written to " + tapdump_prefix + ".f32"
if dflash2_enabled
  rate = drafted == 0 ? ~0.0 : (~0.0 + accepted) / drafted
  << "dflash2: " + accepted.to_s + "/" + drafted.to_s + " drafts accepted (" + rate.to_s + "), " + dflash2_rounds.to_s + " block rounds, " + ((~0.0 + n_generate) / (dflash2_rounds > 0 ? dflash2_rounds : 1)).to_s + " tokens/round"
if mtp_enabled
  rate = drafted == 0 ? ~0.0 : (~0.0 + accepted) / drafted
  << "mtp: " + accepted.to_s + "/" + drafted.to_s + " drafts accepted (" + rate.to_s + ")"
  if draft_rank_probe && rank_samples > 0
    # Cumulative coverage: P(rank < k) is the ceiling on what a k-branch tree
    # can accept per round, since a tree verifies the head's top k candidates.
    cum = 0
    k = 0
    while k < 6
      cum = cum + rank_hist[k]
      label = k < 5 ? ("rank<" + (k + 1).to_s) : "rank<inf"
      cov = (~0.0 + cum) / rank_samples
      << "draft " + label + ": " + cum.to_s + "/" + rank_samples.to_s + " (" + cov.to_s + ")"
      k = k + 1
    << "draft outside compact vocab: " + rank_outside.to_s + "/" + rank_samples.to_s
  if mtp_depth2
    deep_rate = deep_drafted == 0 ? ~0.0 : (~0.0 + deep_accepted) / deep_drafted
    << "mtp depth-2: " + deep_accepted.to_s + "/" + deep_drafted.to_s + " accepted (" + deep_rate.to_s + ")"
  if mtp_adaptive
    score1 = ~0.0
    score2 = ~0.0
    if mtp_auto_ms[0] != ~0.0
      score1 = (~0.0 + mtp_auto_tokens[0]) * 1000.0 / mtp_auto_ms[0]
    if mtp_auto_ms[1] != ~0.0
      score2 = (~0.0 + mtp_auto_tokens[1]) * 1000.0 / mtp_auto_ms[1]
    selected_depth = score2 > score1 ? 2 : 1
    auto_msg = "mtp auto: depth1=" + mtp_auto_rounds[0].to_s
    auto_msg = auto_msg + " rounds/" + score1.to_s + " tok/s, depth2="
    auto_msg = auto_msg + mtp_auto_rounds[1].to_s + " rounds/"
    auto_msg = auto_msg + score2.to_s + " tok/s -> depth " + selected_depth.to_s
    << auto_msg
<< "decode: " + n_generate.to_s + " tokens in " + elapsed.to_s + " ms, " + tokens_per_second.to_s + " tok/s"
if profile_components
  << "components: setup=" + setup_elapsed.to_s + " ms"
  << "components: prefill=" + prefill_elapsed.to_s + " ms, " + ((~0.0 + prompt.size()) * ~1000.0 / prefill_elapsed).to_s + " tok/s"
  << "components: prefill-target=" + profile_stats[3].to_s + " ms/" + profile_stats[4].to_s
  << "components: first-weight-touch=" + profile_stats[15].to_s + " ms, warm-prefill=" + profile_stats[16].to_s + " ms/" + (profile_stats[4] - 1).to_s
  << "components: decode-target=" + profile_stats[1].to_s + " ms/" + profile_stats[2].to_s
  << "components: verify=" + profile_stats[5].to_s + " ms/" + profile_stats[6].to_s
  << "components: draft=" + profile_stats[7].to_s + " ms/" + profile_stats[8].to_s
  << "components: history=" + profile_stats[9].to_s + " ms/" + profile_stats[10].to_s
  << "components: hidden-copy=" + profile_stats[11].to_s + " ms/" + profile_stats[12].to_s
  << "components: rollback=" + profile_stats[13].to_s + " ms/" + profile_stats[14].to_s
