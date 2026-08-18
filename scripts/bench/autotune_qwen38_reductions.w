# Reduction autotune for the Qwen3.8 decode path.
#
# WHY THIS EXISTS. The kernel autotune sweeps matvec shapes only. Every
# reduction on the decode path -- the vocabulary argmax, the MTP draft-vocabulary
# selector, RMSNorm -- was outside its coverage, and that is where the single
# largest win of the 2026-08-18 session was hiding: mtp_compact_draft_select
# scanned 98,330 logits with ONE 32-thread simdgroup, and scanned them TWICE
# (once for the maximum, once to recover its index). It cost a large fraction of
# the MTP head step, which is the term that caps draft depth. The identical
# defect had already been found and fixed for the full-vocabulary argmax in this
# repo (1,648 us -> 3.92 us) and simply never applied to the draft path.
#
# THE GENERAL RULE THIS ENCODES. A reduction over N floats reads 4N bytes and
# should run near memory bandwidth. If its effective throughput is two orders of
# magnitude below that, it is not a tuning opportunity -- it is a serial scan
# wearing a kernel's clothing, and the fix is structural (tile it) rather than
# a parameter. So this tool reports GB/s, not microseconds, and flags anything
# under SERIAL_SCAN_GB_S.
#
# Needs no model weights: synthetic logits are enough to expose the shape.

use core/metal

SHARED_DIR = "bits/tungsten-llama/lib/kernels/shared/"
QWEN_DIR = "bits/tungsten-llama/lib/kernels/qwen3_6/"

N_VOCAB = 248320
MTP_DRAFT_PREFIX = 98304
MTP_DRAFT_CONTROL_START = 248044
MTP_DRAFT_CONTROL_COUNT = 26
MTP_DRAFT_CONTROL_ROWS = 32
ARGMAX_CHUNKS = (N_VOCAB + 1023) / 1024
DRAFT_TILES = (MTP_DRAFT_PREFIX + MTP_DRAFT_CONTROL_COUNT + 1023) / 1024
WARMUP_ITERS = 3
MEASURE_ITERS = 20
# A reduction below this is a serial scan, not a slow kernel. The box sustains
# ~430 GB/s on the real forward; anything under 5% of that is structural.
SERIAL_SCAN_GB_S = ~20.0

device = metal_device()
queue = metal_queue(device)
findings = []

argmax_lib = metal_compile_source(device, read_file(SHARED_DIR + "argmax.metal"))
argmax_pipe = metal_pipeline(argmax_lib, "argmax")
two_stage_lib = metal_compile_source(device, read_file(SHARED_DIR + "argmax_two_stage.metal"))
argmax_s1 = metal_pipeline(two_stage_lib, "argmax_stage1")
argmax_s2 = metal_pipeline(two_stage_lib, "argmax_stage2")
sel_lib = metal_compile_source(device, read_file(QWEN_DIR + "mtp_draft_select.metal"))
sel_pipe = metal_pipeline(sel_lib, "mtp_compact_draft_select")
selfast_lib = metal_compile_source(device, read_file(QWEN_DIR + "mtp_draft_select_fast.metal"))
sel_s1 = metal_pipeline(selfast_lib, "mtp_draft_select_stage1")
sel_s2 = metal_pipeline(selfast_lib, "mtp_draft_select_stage2")

logits = metal_buffer(device, 4 * N_VOCAB * 4)
prefix_logits = metal_buffer(device, MTP_DRAFT_PREFIX * 4)
control_logits = metal_buffer(device, MTP_DRAFT_CONTROL_ROWS * 4)
out_i = metal_buffer(device, 8 * 4)
pv = metal_buffer(device, 4 * ARGMAX_CHUNKS * 4)
pi = metal_buffer(device, 4 * ARGMAX_CHUNKS * 4)
dv = metal_buffer(device, DRAFT_TILES * 4)
di = metal_buffer(device, DRAFT_TILES * 4)
n_vocab_buf = metal_buffer(device, 4)
metal_buffer_write_i32(n_vocab_buf, 0, N_VOCAB)

i = 0
while i < N_VOCAB
  metal_buffer_write_f32(logits, i, Math.sin(i * ~0.0007) * ~10.0)
  i = i + 1
i = 0
while i < MTP_DRAFT_PREFIX
  metal_buffer_write_f32(prefix_logits, i, Math.sin(i * ~0.0011) * ~10.0)
  i = i + 1
i = 0
while i < MTP_DRAFT_CONTROL_ROWS
  metal_buffer_write_f32(control_logits, i, Math.cos(i * ~0.13) * ~3.0)
  i = i + 1

-> dispatch(spec)
  metal_dispatch_groups(queue, spec[0], spec[1], spec[2], spec[3])

-> time_specs(specs)
  metal_batch_begin(queue)
  w = 0
  while w < WARMUP_ITERS
    j = 0
    while j < specs.size()
      dispatch(specs[j])
      j = j + 1
    w = w + 1
  metal_batch_commit(queue)
  metal_batch_begin(queue)
  w = 0
  while w < MEASURE_ITERS
    j = 0
    while j < specs.size()
      dispatch(specs[j])
      j = j + 1
    w = w + 1
  ms = metal_batch_commit_ms(queue, 0)
  (ms / MEASURE_ITERS) * ~1000.0

-> median3(a, b, c)
  lo = a
  if b < lo then lo = b
  if c < lo then lo = c
  hi = a
  if b > hi then hi = b
  if c > hi then hi = c
  a + b + c - lo - hi

-> report(spec)
  name = spec[0]
  elems = spec[1]
  specs = spec[2]
  us = median3(time_specs(specs), time_specs(specs), time_specs(specs))
  gbs = (elems * ~4.0) / (us * ~1000.0)
  line = "  " + name + ": " + us.to_s + " us, " + gbs.to_s + " GB/s"
  << line
  if gbs < SERIAL_SCAN_GB_S
    findings.push("SERIAL SCAN  " + name + ": " + gbs.to_s
      + " GB/s over " + elems.to_s
      + " elements. A reduction should run near memory bandwidth; this is"
      + " two orders of magnitude under it, which means a single simdgroup is"
      + " walking the whole array. Tile it (1024-element first stage plus one"
      + " final reduction) rather than tuning it.")
  us

<< "Qwen3.8 decode-path reduction autotune (synthetic logits, median of 3x" + MEASURE_ITERS.to_s + ")"

<< "full-vocabulary argmax, " + N_VOCAB.to_s + " logits:"
legacy1 = report(["legacy single-simdgroup, width 1", N_VOCAB,
  [[argmax_pipe, [logits, out_i, n_vocab_buf], 1, 32]]])
tiled1 = ~0.0
b = 1
while b <= 4
  tiled = report(["two-stage tiled, width " + b.to_s, N_VOCAB * b,
    [[argmax_s1, [logits, pv, pi, N_VOCAB, ARGMAX_CHUNKS, b], b * ARGMAX_CHUNKS, 256],
     [argmax_s2, [pv, pi, out_i, ARGMAX_CHUNKS, b], b, 256]]])
  if b == 1 then tiled1 = tiled
  b = b + 1

<< "MTP draft-vocabulary select, " + (MTP_DRAFT_PREFIX + MTP_DRAFT_CONTROL_COUNT).to_s + " logits:"
sel_old = report(["legacy single-simdgroup (two passes)",
  MTP_DRAFT_PREFIX + MTP_DRAFT_CONTROL_COUNT,
  [[sel_pipe, [prefix_logits, control_logits, out_i,
     MTP_DRAFT_PREFIX, MTP_DRAFT_CONTROL_COUNT, MTP_DRAFT_CONTROL_START], 1, 32]]])
sel_new = report(["two-stage tiled",
  MTP_DRAFT_PREFIX + MTP_DRAFT_CONTROL_COUNT,
  [[sel_s1, [prefix_logits, control_logits, dv, di,
     MTP_DRAFT_PREFIX, MTP_DRAFT_CONTROL_COUNT, MTP_DRAFT_CONTROL_START],
    DRAFT_TILES, 256],
   [sel_s2, [dv, di, out_i, DRAFT_TILES], 1, 256]]])
<< "  draft select speedup: " + (sel_old / sel_new).to_s + "x"
<< "  full-vocab argmax legacy-vs-tiled speedup: " + (legacy1 / tiled1).to_s + "x"

<< ""
if findings.size() == 0
  << "reduction autotune done -- every reduction runs at a sane throughput"
else
  << "=============================================================="
  << "REDUCTION FINDINGS (" + findings.size().to_s + ")"
  << "=============================================================="
  fi = 0
  while fi < findings.size()
    << findings[fi]
    fi = fi + 1
  << "=============================================================="
  << "reduction autotune done -- " + findings.size().to_s + " finding(s)"
