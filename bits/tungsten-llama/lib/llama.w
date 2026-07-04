# llama — multi-subcommand entry point for the tungsten-llama bit.
#
# Subcommands:
#   serve <model>      Load a model and run a stdin/stdout request loop.
#                      Supported models: lightning
#
# Server protocol (stdin/stdout, one prompt per line):
#   READY\n                      emitted once on startup, after model load
#   <prompt-text>\n              request: a single line of text
#   <response-text>\n            response: a single line of text (newlines
#                                in the generated text are escaped as \n)
#   ERROR <message>\n            non-fatal error (request-scoped)
#
# The REPL is responsible for ensuring the tokenizer's packed cache
# (`<tokenizer.json>.bin`) exists before invoking — see
# bits/tungsten-llama/scripts/tokenizer_pack.py.

use core/metal
use core/json
use tungsten-llama/safetensors
use tungsten-llama/tokenizer

in Tungsten:Llama

# ── Read one line from stdin ─────────────────────────────────────────
# core/global.w declares `gets` but the C runtime never exposes it; do
# it ourselves on top of read_bytes(1).
-> read_line
  buf = StringBuffer(0)
  while true
    chunk = read_bytes(1)
    if chunk == nil || chunk.size() == 0
      if buf.size() == 0
        return nil
      return buf.to_s()
    if chunk == "\n"
      return buf.to_s()
    buf << chunk

# ── Lightning-1.7B serve ─────────────────────────────────────────────
# All state lives at module scope so the per-step fns can capture it.
# Slots are nil until `serve lightning` actually loads — that way other
# subcommands (e.g. `--help`) don't pay the model-load cost.

LIGHTNING_PATH      = "/Users/erik/.cache/huggingface/hub/models--bradyclarke--Lightning-1.7B-mlx-nvfp4/snapshots/93b9599f5380f67efa1faa0dc6591251f040882a/model.safetensors"
LIGHTNING_TOKENIZER = "/Users/erik/.cache/huggingface/hub/models--bradyclarke--Lightning-1.7B-mlx-nvfp4/snapshots/93b9599f5380f67efa1faa0dc6591251f040882a/tokenizer.json.bin"
KERNEL_DIR          = "bits/tungsten-llama/lib/kernels/"
NVFP4_DIR           = "bits/tungsten-llama/lib/kernels/nvfp4/"

HIDDEN        = 2048
HEAD_DIM      = 128
HEAD_DIM_HALF = 64
N_Q_HEADS     = 16
N_KV_HEADS    = 8
GROUP_SIZE    = 2
KV_ROW        = 1024
INTERMEDIATE  = 6144
N_VOCAB       = 151936
N_LAYERS      = 28
EPS           = ~0.000001
BASE          = ~1000000.0
MAX_POS       = 1536               # enough room for 1000-token replies plus prompt
MAX_NEW       = 1000
MAX_WORD      = 8
MAX_SENTENCE  = 80
MAX_PARAGRAPH = 240
REPETITION_WINDOW = 160
REPETITION_PENALTY = ~1.18
NO_REPEAT_NGRAM = 5
SAMPLING_TEMPERATURE = ~0.7
SAMPLING_TOP_K = 40
INV_HIDDEN    = ~1.0 / HIDDEN
INV_HEAD_DIM  = ~1.0 / HEAD_DIM
ATTN_SCALE    = ~1.0 / Math.sqrt(~0.0 + HEAD_DIM)
KDIM_O        = N_Q_HEADS * HEAD_DIM
Q_TGS         = KDIM_O / 8
KV_TGS        = KV_ROW / 8

# Module-level state — assigned in the serve block, captured by the per-
# step fns below. Declared up front (with nil) so the fn defs can refer
# to them by name even before the actual values exist.
device = nil
queue = nil
st = nil
tok = nil

nvfp4_matvec_pipe  = nil
nvfp4_matvec_v4_pipe = nil
nvfp4_mlx_pipe     = nil
nvfp4_mlx_qkv_pipe = nil
nvfp4_mlx_gu_pipe  = nil
nvfp4_mlx_r_pipe   = nil
nvfp4_embed_pipe   = nil
f16_to_f32_pipe    = nil
rms_pipe           = nil
phn_rope_pipe      = nil
phn_rope_kc_pipe   = nil
kv_pipe            = nil
sdpa_pipe          = nil
silu_pipe          = nil
argmax_pipe        = nil

embed     = nil
out_norm  = nil
layers    = nil

x_buf      = nil
xn_buf     = nil
q_buf      = nil
k_buf      = nil
v_buf      = nil
cos_buf    = nil
sin_buf    = nil
scores_buf = nil
attn_out   = nil
attn_proj  = nil
gate_buf   = nil
up_buf     = nil
h_buf      = nil
ffn_out    = nil
logits_buf = nil
argmax_buf = nil

hidden_buf   = nil
inv_h_buf    = nil
eps_buf      = nil
hd_buf       = nil
inv_d_buf    = nil
hdh_buf      = nil
n_q_buf      = nil
n_kv_buf     = nil
gs_buf       = nil
scale_buf    = nil
kv_row_buf   = nil
pos_buf      = nil
n_pos_buf    = nil
kdim_h_buf   = nil
kdim_o_buf   = nil
kdim_int_buf = nil
n_silu_buf   = nil
n_vocab_buf  = nil
token_id_buf = nil

log_base = Math.log(BASE)
inv_hd   = ~2.0 / HEAD_DIM

-> upload_f16_as_f32(name)
  desc = st.tensor(name)
  n_floats = desc[:byte_length] / 2
  src_buf = metal_buffer(device, desc[:byte_length])
  dst_buf = metal_buffer(device, n_floats * 4)
  st.upload_bytes(name, src_buf)
  n_buf = metal_buffer(device, 4)
  metal_buffer_write_i32(n_buf, 0, n_floats)
  metal_batch_begin(queue)
  metal_dispatch_n(queue, f16_to_f32_pipe, [src_buf, dst_buf, n_buf], n_floats)
  metal_batch_commit(queue)
  dst_buf

-> upload_nvfp4(name)
  w_desc = st.tensor(name + ".weight")
  s_desc = st.tensor(name + ".scales")
  w_buf = metal_buffer(device, w_desc[:byte_length])
  s_buf = metal_buffer(device, s_desc[:byte_length])
  st.upload_bytes(name + ".weight", w_buf)
  st.upload_bytes(name + ".scales", s_buf)
  { quants: w_buf, scales: s_buf }

-> build_rope_tables(pos)
  i = 0
  while i < HEAD_DIM_HALF
    theta = Math.exp(log_base * (~0.0 - i * inv_hd))
    angle = pos * theta
    metal_buffer_write_f32(cos_buf, i, Math.cos(angle))
    metal_buffer_write_f32(sin_buf, i, Math.sin(angle))
    i = i + 1

-> run_block(lyr, n_pos_active)
  metal_dispatch_groups(queue, rms_pipe, [x_buf, lyr[:attn_norm], xn_buf, HIDDEN, INV_HIDDEN, EPS], 1, 512)
  metal_batch_barrier(queue)
  metal_dispatch_groups(queue, nvfp4_mlx_qkv_pipe, [
    lyr[:q_proj][:quants], lyr[:q_proj][:scales],
    lyr[:k_proj][:quants], lyr[:k_proj][:scales],
    lyr[:v_proj][:quants], lyr[:v_proj][:scales],
    xn_buf, q_buf, k_buf, v_buf,
    HIDDEN, Q_TGS, KV_TGS
  ], Q_TGS + KV_TGS + KV_TGS, 64)
  metal_batch_barrier(queue)
  metal_dispatch_groups(queue, phn_rope_pipe, [q_buf, lyr[:q_norm], cos_buf, sin_buf, HEAD_DIM, HEAD_DIM_HALF, INV_HEAD_DIM, EPS], N_Q_HEADS, 32)
  metal_dispatch_groups(queue, phn_rope_kc_pipe, [k_buf, lyr[:k_norm], cos_buf, sin_buf, lyr[:k_cache], HEAD_DIM, HEAD_DIM_HALF, pos_buf, KV_ROW, INV_HEAD_DIM, EPS], N_KV_HEADS, 32)
  metal_dispatch_n(queue, kv_pipe, [v_buf, lyr[:v_cache], pos_buf, KV_ROW], KV_ROW)
  metal_batch_barrier(queue)
  metal_dispatch_groups(queue, sdpa_pipe, [q_buf, lyr[:k_cache], lyr[:v_cache], attn_out, GROUP_SIZE, n_pos_buf, HEAD_DIM, KV_ROW, ATTN_SCALE], N_Q_HEADS, 1024)
  metal_batch_barrier(queue)
  metal_dispatch_groups(queue, nvfp4_mlx_r_pipe, [lyr[:o_proj][:quants], lyr[:o_proj][:scales], attn_out, x_buf, KDIM_O], HIDDEN / 8, 64)
  metal_batch_barrier(queue)
  metal_dispatch_groups(queue, rms_pipe, [x_buf, lyr[:ffn_norm], xn_buf, HIDDEN, INV_HIDDEN, EPS], 1, 512)
  metal_batch_barrier(queue)
  metal_dispatch_groups(queue, nvfp4_mlx_gu_pipe, [
    lyr[:gate_proj][:quants], lyr[:gate_proj][:scales],
    lyr[:up_proj][:quants], lyr[:up_proj][:scales],
    xn_buf, gate_buf, up_buf,
    HIDDEN, INTERMEDIATE / 8
  ], (INTERMEDIATE / 8) * 2, 64)
  metal_batch_barrier(queue)
  metal_dispatch_n(queue, silu_pipe, [gate_buf, up_buf, h_buf, n_silu_buf], INTERMEDIATE)
  metal_batch_barrier(queue)
  metal_dispatch_groups(queue, nvfp4_mlx_r_pipe, [lyr[:down_proj][:quants], lyr[:down_proj][:scales], h_buf, x_buf, INTERMEDIATE], HIDDEN / 8, 64)
  metal_batch_barrier(queue)

-> forward_logits(token_id, pos)
  metal_buffer_write_i32(pos_buf, 0, pos)
  n_pos_active = pos + 1
  metal_buffer_write_i32(n_pos_buf, 0, n_pos_active)
  metal_buffer_write_i32(token_id_buf, 0, token_id)

  build_rope_tables(pos)

  metal_batch_begin_concurrent(queue)
  metal_dispatch_n(queue, nvfp4_embed_pipe, [embed[:quants], embed[:scales], x_buf, token_id_buf, kdim_h_buf], HIDDEN / 16)
  metal_batch_barrier(queue)
  li = 0
  while li < N_LAYERS
    run_block(layers[li], n_pos_active)
    li = li + 1
  metal_dispatch_groups(queue, rms_pipe, [x_buf, out_norm, xn_buf, HIDDEN, INV_HIDDEN, EPS], 1, 512)
  metal_batch_barrier(queue)
  metal_set_threadgroup_memory(queue, HIDDEN * 4, 0)
  metal_dispatch_groups(queue, nvfp4_matvec_v4_pipe, [embed[:quants], embed[:scales], xn_buf, logits_buf, HIDDEN], N_VOCAB / 32, 1024)
  metal_batch_barrier(queue)
  metal_batch_commit(queue)

-> forward_step(token_id, pos)
  forward_logits(token_id, pos)
  metal_batch_begin_concurrent(queue)
  metal_dispatch_groups(queue, argmax_pipe, [logits_buf, argmax_buf, N_VOCAB], 1, 1024)
  metal_batch_commit(queue)
  metal_buffer_read_i32(argmax_buf, 0)

-> recent_token_set(ids)
  seen = {}
  start = ids.size() - REPETITION_WINDOW
  if start < 0
    start = 0
  i = start
  while i < ids.size()
    seen[ids[i]] = true
    i = i + 1
  seen

-> no_repeat_bans(ids)
  bans = {}
  if NO_REPEAT_NGRAM <= 1 || ids.size() < NO_REPEAT_NGRAM - 1
    return bans

  suffix_start = ids.size() - (NO_REPEAT_NGRAM - 1)
  limit = ids.size() - NO_REPEAT_NGRAM
  i = 0
  while i <= limit
    matched = true
    j = 0
    while j < NO_REPEAT_NGRAM - 1
      if ids[i + j] != ids[suffix_start + j]
        matched = false
        break
      j = j + 1
    if matched
      bans[ids[i + NO_REPEAT_NGRAM - 1]] = true
    i = i + 1
  bans

-> xorshift48(state)
  s = state ^ ((state << 13) & 0xFFFFFFFFFFFF)
  s = s ^ (s >> 7)
  s = s ^ ((s << 17) & 0xFFFFFFFFFFFF)
  s & 0xFFFFFFFFFFFF

-> rng_uniform(state)
  bits = state & 0xFFFFFF
  bits * (~1.0 / ~16777216.0)

-> adjusted_logit(token_id, seen)
  v = metal_buffer_read_f32(logits_buf, token_id)
  if seen.has_key?(token_id)
    if v > ~0.0
      return v / REPETITION_PENALTY
    return v * REPETITION_PENALTY
  v

-> select_greedy_token(seen, bans)
  best = 0
  best_v = ~-1000000000.0
  i = 0
  while i < N_VOCAB
    if !bans.has_key?(i)
      v = adjusted_logit(i, seen)
      if v > best_v
        best_v = v
        best = i
    i = i + 1
  best

-> sample_top_k_token(seen, bans, rng_state)
  top_idx = []
  top_val = []
  i = 0
  while i < N_VOCAB
    if !bans.has_key?(i)
      v = adjusted_logit(i, seen)
      if top_idx.size() < SAMPLING_TOP_K
        top_idx.push(i)
        top_val.push(v)
      else
        worst = 0
        worst_v = top_val[0]
        j = 1
        while j < SAMPLING_TOP_K
          if top_val[j] < worst_v
            worst_v = top_val[j]
            worst = j
          j = j + 1
        if v > worst_v
          top_idx[worst] = i
          top_val[worst] = v
    i = i + 1

  if top_idx.size() == 0
    return [0, rng_state]

  max_v = top_val[0]
  i = 1
  while i < top_val.size()
    if top_val[i] > max_v
      max_v = top_val[i]
    i = i + 1

  inv_t = ~1.0 / SAMPLING_TEMPERATURE
  sum_e = ~0.0
  i = 0
  while i < top_val.size()
    e = Math.exp((top_val[i] - max_v) * inv_t)
    top_val[i] = e
    sum_e = sum_e + e
    i = i + 1

  rng_state = xorshift48(rng_state)
  threshold = rng_uniform(rng_state) * sum_e
  cumulative = ~0.0
  i = 0
  while i < top_val.size()
    cumulative = cumulative + top_val[i]
    if cumulative > threshold
      return [top_idx[i], rng_state]
    i = i + 1
  [top_idx[top_idx.size() - 1], rng_state]

-> select_next_token(generated_ids, sample, rng_state)
  seen = recent_token_set(generated_ids)
  bans = no_repeat_bans(generated_ids)
  if sample
    return sample_top_k_token(seen, bans, rng_state)
  [select_greedy_token(seen, bans), rng_state]

# ── Generate up to `max_new` tokens after prefill of `prompt_ids` ────
# Returns the array of generated token ids (excluding prompt). Stops
# early if the model emits the eos token.
-> generate(prompt_ids, max_new, eos_id)
  if prompt_ids.size() == 0
    return []
  if prompt_ids.size() >= MAX_POS
    raise "llama serve: prompt is " + prompt_ids.size().to_s + " tokens (limit " + MAX_POS.to_s + ")"

  decode_mode = env("LLAMA_DECODE")
  selected_decode = decode_mode == "sample" || decode_mode == "guarded"
  sample = decode_mode == "sample"

  if !selected_decode
    pos = 0
    last = -1
    i = 0
    while i < prompt_ids.size()
      last = forward_step(prompt_ids[i], pos)
      pos = pos + 1
      i = i + 1

    out = []
    step = 0
    while step < max_new && pos < MAX_POS
      out.push(last)
      if eos_id != nil && last == eos_id
        return out
      last = forward_step(last, pos)
      pos = pos + 1
      step = step + 1
    return out

  rng_state = ccall("__w_clock_ms") & 0xFFFFFFFFFFFF
  rng_state = rng_state ^ ((prompt_ids.size() + max_new) & 0xFFFFFFFFFFFF)
  if rng_state == 0
    rng_state = 1

  pos = 0
  i = 0
  while i < prompt_ids.size()
    forward_logits(prompt_ids[i], pos)
    pos = pos + 1
    i = i + 1

  out = []
  step = 0
  while step < max_new && pos < MAX_POS
    choice = select_next_token(out, sample, rng_state)
    last = choice[0]
    rng_state = choice[1]
    out.push(last)
    if eos_id != nil && last == eos_id
      return out
    forward_logits(last, pos)
    pos = pos + 1
    step = step + 1
  out

# ── Escape \n / \r in a generated chunk so the response stays one line.
-> escape_newlines(s)
  bytes = s.bytes
  out = StringBuffer(bytes.size())
  i = 0
  while i < bytes.size()
    b = bytes[i]
    if b == 10
      out << "\\n"
    elsif b == 13
      out << "\\r"
    else
      out << byte_to_str(b)
    i = i + 1
  out.to_s()

-> max_new_for_prompt(prompt)
  if prompt.starts_with?("Answer in one word.")
    return MAX_WORD
  if prompt.starts_with?("Answer in one short sentence.")
    return MAX_SENTENCE
  if prompt.starts_with?("Answer in one paragraph.")
    return MAX_PARAGRAPH
  MAX_NEW

# ── argv dispatch ─────────────────────────────────────────────────────

args = argv()

if args.size() == 0
  << "Usage: llama <subcommand> [args]"
  << ""
  << "Subcommands:"
  << "  serve <model>    Run a stdin/stdout inference server"
  exit 0

cmd = args[0]

if cmd == "serve"
  if args.size() < 2
    STDERR << "llama serve: missing model name (try: lightning)"
    exit 1
  model = args[1]
  if model == "lightning"
    # ── Load tokenizer ──
    tok = Tokenizer.from_packed_tokenizer(LIGHTNING_TOKENIZER)

    # ── Load model ──
    device = metal_device()
    queue  = metal_queue(device)
    st     = Safetensors.new(LIGHTNING_PATH)

    nvfp4_matvec_pipe = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec.metal")), "nvfp4_matvec")
    nvfp4_matvec_v4_pipe = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_v4.metal")), "nvfp4_matvec_v4")
    nvfp4_mlx_pipe    = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx.metal")), "nvfp4_matvec_mlx")
    nvfp4_mlx_qkv_pipe = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_qkv.metal")), "nvfp4_matvec_mlx_qkv")
    nvfp4_mlx_gu_pipe = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_gu.metal")), "nvfp4_matvec_mlx_gu")
    nvfp4_mlx_r_pipe = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_residual.metal")), "nvfp4_matvec_mlx_residual")
    nvfp4_embed_pipe  = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_embedding_lookup.metal")), "nvfp4_embedding_lookup")
    f16_to_f32_pipe   = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "f16_to_f32.metal")), "f16_to_f32")
    rms_pipe       = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "shared/rms_norm.metal")), "rms_norm")
    phn_rope_pipe  = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "shared/per_head_norm_rope.metal")), "per_head_norm_rope")
    phn_rope_kc_pipe = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "shared/per_head_norm_rope_to_cache_bf16.metal")), "per_head_norm_rope_to_cache_bf16")
    kv_pipe        = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "shared/kv_write_bf16.metal")), "kv_write_bf16")
    sdpa_pipe      = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "shared/sdpa_vector_bf16.metal")), "sdpa_vector_bf16")
    silu_pipe      = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "shared/silu_mul.metal")), "silu_mul")
    argmax_pipe    = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "shared/argmax.metal")), "argmax")

    embed = upload_nvfp4("model.embed_tokens")

    layers = []
    li = 0
    while li < N_LAYERS
      prefix = "model.layers." + li.to_s + "."
      layers.push({
        attn_norm: upload_f16_as_f32(prefix + "input_layernorm.weight"),
        q_proj:    upload_nvfp4(prefix + "self_attn.q_proj"),
        k_proj:    upload_nvfp4(prefix + "self_attn.k_proj"),
        v_proj:    upload_nvfp4(prefix + "self_attn.v_proj"),
        o_proj:    upload_nvfp4(prefix + "self_attn.o_proj"),
        q_norm:    upload_f16_as_f32(prefix + "self_attn.q_norm.weight"),
        k_norm:    upload_f16_as_f32(prefix + "self_attn.k_norm.weight"),
        ffn_norm:  upload_f16_as_f32(prefix + "post_attention_layernorm.weight"),
        gate_proj: upload_nvfp4(prefix + "mlp.gate_proj"),
        up_proj:   upload_nvfp4(prefix + "mlp.up_proj"),
        down_proj: upload_nvfp4(prefix + "mlp.down_proj"),
        k_cache:   metal_buffer(device, MAX_POS * KV_ROW * 2),
        v_cache:   metal_buffer(device, MAX_POS * KV_ROW * 2)
      })
      li = li + 1

    out_norm = upload_f16_as_f32("model.norm.weight")

    x_buf      = metal_buffer(device, HIDDEN * 4)
    xn_buf     = metal_buffer(device, HIDDEN * 4)
    q_buf      = metal_buffer(device, N_Q_HEADS * HEAD_DIM * 4)
    k_buf      = metal_buffer(device, KV_ROW * 4)
    v_buf      = metal_buffer(device, KV_ROW * 4)
    cos_buf    = metal_buffer(device, HEAD_DIM_HALF * 4)
    sin_buf    = metal_buffer(device, HEAD_DIM_HALF * 4)
    scores_buf = metal_buffer(device, N_Q_HEADS * MAX_POS * 4)
    attn_out   = metal_buffer(device, N_Q_HEADS * HEAD_DIM * 4)
    attn_proj  = metal_buffer(device, HIDDEN * 4)
    gate_buf   = metal_buffer(device, INTERMEDIATE * 4)
    up_buf     = metal_buffer(device, INTERMEDIATE * 4)
    h_buf      = metal_buffer(device, INTERMEDIATE * 4)
    ffn_out    = metal_buffer(device, HIDDEN * 4)
    logits_buf = metal_buffer(device, N_VOCAB * 4)
    argmax_buf = metal_buffer(device, 4)

    hidden_buf  = metal_buffer(device, 4) ; metal_buffer_write_i32(hidden_buf, 0, HIDDEN)
    inv_h_buf   = metal_buffer(device, 4) ; metal_buffer_write_f32(inv_h_buf, 0, ~1.0 / HIDDEN)
    eps_buf     = metal_buffer(device, 4) ; metal_buffer_write_f32(eps_buf, 0, EPS)
    hd_buf      = metal_buffer(device, 4) ; metal_buffer_write_i32(hd_buf, 0, HEAD_DIM)
    inv_d_buf   = metal_buffer(device, 4) ; metal_buffer_write_f32(inv_d_buf, 0, ~1.0 / HEAD_DIM)
    hdh_buf     = metal_buffer(device, 4) ; metal_buffer_write_i32(hdh_buf, 0, HEAD_DIM_HALF)
    n_q_buf     = metal_buffer(device, 4) ; metal_buffer_write_i32(n_q_buf, 0, N_Q_HEADS)
    n_kv_buf    = metal_buffer(device, 4) ; metal_buffer_write_i32(n_kv_buf, 0, N_KV_HEADS)
    gs_buf      = metal_buffer(device, 4) ; metal_buffer_write_i32(gs_buf, 0, GROUP_SIZE)
    scale_buf   = metal_buffer(device, 4) ; metal_buffer_write_f32(scale_buf, 0, ~1.0 / Math.sqrt(~0.0 + HEAD_DIM))
    kv_row_buf  = metal_buffer(device, 4) ; metal_buffer_write_i32(kv_row_buf, 0, KV_ROW)
    pos_buf     = metal_buffer(device, 4)
    n_pos_buf   = metal_buffer(device, 4)
    kdim_h_buf  = metal_buffer(device, 4) ; metal_buffer_write_i32(kdim_h_buf, 0, HIDDEN)
    kdim_o_buf  = metal_buffer(device, 4) ; metal_buffer_write_i32(kdim_o_buf, 0, N_Q_HEADS * HEAD_DIM)
    kdim_int_buf = metal_buffer(device, 4) ; metal_buffer_write_i32(kdim_int_buf, 0, INTERMEDIATE)
    n_silu_buf  = metal_buffer(device, 4) ; metal_buffer_write_i32(n_silu_buf, 0, INTERMEDIATE)
    n_vocab_buf = metal_buffer(device, 4) ; metal_buffer_write_i32(n_vocab_buf, 0, N_VOCAB)
    token_id_buf = metal_buffer(device, 4)

    # ── Request loop ──
    << "READY"
    flush
    while true
      line = read_line()
      if line == nil
        break
      prompt = line.strip
      if prompt == ""
        next

      ids = tok.encode(prompt)
      response_ids = generate(ids, max_new_for_prompt(prompt), tok.eos_id)
      text = tok.decode(response_ids)
      << escape_newlines(text)
      flush

    exit 0
  else
    STDERR << "llama serve: unknown model: " + model
    exit 1
else
  STDERR << "llama: unknown subcommand: " + cmd
  exit 1
