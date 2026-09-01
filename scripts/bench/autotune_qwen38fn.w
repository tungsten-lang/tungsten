# Autotune the Qwen3.8-Flash-Next decode kernels on real weights.
#
# The model's decode cost is dominated by bf16 weight streams (~9.7 GB/token),
# so the first axis is the bf16 matvec family: the shared 1-row/simdgroup
# kernel vs the qwen4_fn wide variants (2 and 4 rows/simdgroup, ushort4
# loads), swept over every decode matvec shape at its real tensor. Arms are
# interleaved within one process and reported as median effective GB/s.
#
#   scripts/bench/perf_lock.sh bin/tungsten run scripts/bench/autotune_qwen38fn.w
#
# Add "gather" as ARGV[0] to also sweep the MoE gather kernel's expert count.

use core/metal
use core/json
use tungsten-llama/sharded_safetensors

MODEL_DIR = "/Users/erik/.cache/tungsten/qwen38-flash-next-nvfp4/"
SHARED_DIR = "bits/tungsten-llama/lib/kernels/shared/"
FN_DIR = "bits/tungsten-llama/lib/kernels/qwen4_fn/"

device = metal_device()
queue = metal_queue(device)
st = Tungsten:Llama:ShardedSafetensors.new(MODEL_DIR + "index.slim.json")

bf16_pipe = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "bf16_matvec.metal")), "bf16_matvec")
wide_lib = metal_compile_source(device, read_file(FN_DIR + "bf16_matvec_wide.metal"))
w2_pipe = metal_pipeline(wide_lib, "bf16_matvec_w2")
w4_pipe = metal_pipeline(wide_lib, "bf16_matvec_w4")

-> raw_tensor(name)
  d = st.tensor(name)
  metal_buffer_for_mmap(device, st.mmap_for(name), d[:byte_offset], d[:byte_length])

# Each shape binds the SAME tensor from many layers and the timed batch
# rotates through them, so a pass streams cold pages instead of re-reading
# one SLC-resident tile (which reports impossible >1TB/s and inverts
# rankings — the isolated-timing trap from the qwen38 bakeoffs).
L = "model.language_model.layers."
gdn_layers = [4, 5, 6, 8, 9, 10, 12, 13, 14, 16, 17, 18]
attn_layers = [3, 7, 11, 15, 19, 23, 27, 31, 35, 39, 43, 47]
-> layer_names(spec)
  lys = spec[0]
  suffix = spec[1]
  names = []
  i = 0
  while i < lys.size()
    names.push(L + lys[i].to_s + "." + suffix)
    i = i + 1
  names

shapes = [
  ["gdn qkv 10240x2560", layer_names([gdn_layers, "linear_attn.in_proj_qkv.weight"]), 10240, 2560],
  ["gdn z 6144x2560", layer_names([gdn_layers, "linear_attn.in_proj_z.weight"]), 6144, 2560],
  ["gdn out 2560x6144", layer_names([gdn_layers, "linear_attn.out_proj.weight"]), 2560, 6144],
  ["attn q 12288x2560", layer_names([attn_layers, "self_attn.q_proj.weight"]), 12288, 2560],
  ["attn kv 512x2560", layer_names([attn_layers, "self_attn.k_proj.weight"]), 512, 2560],
  ["attn o 2560x6144", layer_names([attn_layers, "self_attn.o_proj.weight"]), 2560, 6144],
  ["hc down 320x10240", layer_names([gdn_layers, "attn_hyper_connection.input_mix_weight_down.weight"]), 320, 10240],
  ["hc up 10240x320", layer_names([gdn_layers, "attn_hyper_connection.input_mix_weight_up.weight"]), 10240, 320],
  ["router 512x2560", layer_names([gdn_layers, "mlp.gate.weight"]), 512, 2560],
  ["shared gu 640x2560", layer_names([gdn_layers, "mlp.shared_expert.gate_proj.weight"]), 640, 2560],
  ["shared dn 2560x640", layer_names([gdn_layers, "mlp.shared_expert.down_proj.weight"]), 2560, 640],
  ["lm_head 248320x2560", ["lm_head.weight"], 248320, 2560]
]

x_buf = metal_buffer(device, 10240 * 4)
i = 0
while i < 10240
  metal_buffer_write_f32(x_buf, i, Math.sin(~0.0 + i))
  i = i + 1
y_buf = metal_buffer(device, 248320 * 4)

REPS = 7

-> run_arm(spec)
  variant = spec[0]
  ws = spec[1]
  rows = spec[2]
  kd = spec[3]
  inner = spec[4]
  metal_batch_begin(queue)
  it = 0
  while it < inner
    w = ws[it % ws.size()]
    if variant == 0
      metal_dispatch_groups(queue, bf16_pipe, [w, x_buf, y_buf, kd], rows, 32)
    elsif variant == 1
      metal_dispatch_groups(queue, w2_pipe, [w, x_buf, y_buf, kd, rows], (rows + 3) / 4, 64)
    else
      metal_dispatch_groups(queue, w4_pipe, [w, x_buf, y_buf, kd, rows], (rows + 7) / 8, 64)
    it = it + 1
  t0 = ccall("__w_clock_ms")
  metal_batch_commit(queue)
  ccall("__w_clock_ms") - t0

names = ["naive", "w2   ", "w4   "]
si = 0
while si < shapes.size()
  s = shapes[si]
  ws = []
  ni = 0
  while ni < s[1].size()
    ws.push(raw_tensor(s[1][ni]))
    ni = ni + 1
  rows = s[2]
  kd = s[3]
  pass_bytes = rows * kd * 2
  # target ~2 GB of weight traffic per timed batch for stable milliseconds
  inner = (2000000000 + pass_bytes - 1) / pass_bytes
  if inner > 4096 then inner = 4096
  # round up to a multiple of the rotation so every tensor streams equally
  inner = ((inner + ws.size() - 1) / ws.size()) * ws.size()
  bytes = (~0.0 + pass_bytes) * inner
  # warm the pages
  run_arm([0, ws, rows, kd, inner])
  run_arm([2, ws, rows, kd, inner])
  medians = []
  v = 0
  while v < 3
    times = []
    r = 0
    while r < REPS
      # interleave: cycle all variants inside each rep
      times.push(run_arm([v, ws, rows, kd, inner]))
      r = r + 1
    ts = times.sort()
    m = ts[ts.size() / 2]
    if m < 1 then m = 1
    medians.push(m)
    v = v + 1
  line = s[0] + ": "
  v = 0
  while v < 3
    gbs = bytes / (medians[v] * 1000000.0)
    line = line + names[v] + " " + medians[v].to_s + "ms (" + gbs.to_i().to_s + " GB/s)  "
    v = v + 1
  << line
  si = si + 1
