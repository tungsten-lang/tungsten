# Try to compile each new decode-batch kernel and report status.
use core/metal

device = metal_device()
KERNEL_DIR = "bits/tungsten-llama/lib/kernels/shared/"

names = [
  "per_head_norm_rope_to_cache_decode_batch_fc",
  "v_write_decode_batch_fc",
  "attn_scores_decode_batch_fc",
  "attn_softmax_decode_batch_fc",
  "attn_weighted_sum_decode_batch_fc",
  "argmax_batch_fc"
]

i = 0
while i < names.size()
  name = names[i]
  << "compile " + name + "..."
  src = read_file(KERNEL_DIR + name + ".metal")
  lib_obj = metal_compile_source(device, src)
  << "  ok"
  i = i + 1
