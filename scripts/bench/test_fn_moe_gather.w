# Layer-level test: qwen4_fn moe_gather_matvec vs numpy (check_fn_moe_gather.py).
#
# Binds layer 0's four quarter shards exactly like qwen38fn_mlx.w, runs the
# gather matvec for a fixed set of 10 experts spanning all quarters (and the
# string-sort slot permutation) on a deterministic input, and dumps the
# [10, 640] gate_proj output. The python twin recomputes it from the same
# files through flash_next_ckpt.nvfp4_dequant and compares.
#
#   bin/tungsten run scripts/bench/test_fn_moe_gather.w
#   python3 scripts/bench/check_fn_moe_gather.py

use core/metal
use core/json

MODEL_DIR = "/Users/erik/.cache/tungsten/qwen38-flash-next-nvfp4/"
FN_DIR = "bits/tungsten-llama/lib/kernels/qwen4_fn/"
HIDDEN = 2560
MOE_FFN = 640
TOP_K = 10
N_EXPERTS = 512
LAYER = 0

test_experts = [0, 1, 2, 10, 100, 127, 128, 300, 500, 511]

device = metal_device()
queue = metal_queue(device)
gather_pipe = metal_pipeline(metal_compile_source(device, read_file(FN_DIR + "moe_gather_nvfp4.metal")), "moe_gather_matvec")

man = JSON.parse(read_file(MODEL_DIR + "experts_manifest.json"))
entries = {}
fi = 0
while fi < man["files"].size()
  e = man["files"][fi]
  if e["layer"] == LAYER then entries[e["quarter"].to_s] = e
  fi = fi + 1

quarters = []
slot_buf = metal_buffer(device, N_EXPERTS * 4)
q = 0
while q < 4
  e = entries[q.to_s]
  if e == nil then raise "layer 0 quarter " + q.to_s + " missing from manifest"
  m = File.mmap(MODEL_DIR + e["file"])
  quarters.push(metal_buffer_for_mmap(device, m, e["data_start"], e["file_size"] - e["data_start"]))
  sm = e["slot_map"]
  j = 0
  while j < 128
    metal_buffer_write_i32(slot_buf, q * 128 + j, sm[j])
    j = j + 1
  q = q + 1

e0 = entries["0"]
gm = e0["gate_proj"]

idx_buf = metal_buffer(device, TOP_K * 4)
i = 0
while i < TOP_K
  metal_buffer_write_i32(idx_buf, i, test_experts[i])
  i = i + 1

# Deterministic integer-derived input, exact in both runtimes.
x_buf = metal_buffer(device, HIDDEN * 4)
i = 0
while i < HIDDEN
  v = ((i * 1103515245 + 12345) % 1000) - 500
  metal_buffer_write_f32(x_buf, i, (~0.0 + v) / 500.0)
  i = i + 1

y_buf = metal_buffer(device, TOP_K * MOE_FFN * 4)
dummy_hot = metal_buffer(device, 8)

metal_batch_begin(queue)
metal_dispatch_groups(queue, gather_pipe,
  [quarters[0], quarters[1], quarters[2], quarters[3], idx_buf, slot_buf, x_buf, y_buf,
   HIDDEN, MOE_FFN, gm["w0"], gm["w_stride"], gm["s0"], gm["s_stride"],
   gm["g0"], gm["g_stride"], 0, dummy_hot, 0, 0, 0],
  TOP_K * (MOE_FFN / 8), 64)
metal_batch_commit(queue)

File.write_bytes("/tmp/fn_moe_gather_y.f32", metal_buffer_view(y_buf, 8, TOP_K * MOE_FFN * 4))
<< "wrote /tmp/fn_moe_gather_y.f32 for experts " + test_experts.to_s
