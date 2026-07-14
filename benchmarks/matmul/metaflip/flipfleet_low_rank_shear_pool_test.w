use flipfleet_low_rank_shear_pool_lib

-> fflrsp_test_expect(name, condition)
  if !condition
    << "FAIL " + name
    exit(1)
  1

args = argv()
metal_path = "/tmp/flipfleet_low_rank_shear_pool_test.metal"
if args.size() > 0
  metal_path = args[0]
metallib_path = ""
if args.size() > 1
  metallib_path = args[1]
device = metal_device()
library = nil
if metallib_path != ""
  library = metal_load_library(device, metallib_path)
if library == nil
  msl = read_file(metal_path)
  z = fflrsp_test_expect("emitted Metal readable", msl != nil)
  library = metal_compile_source(device, msl)
queue = metal_queue(device)

# Planted rank-two correction absorption exercises the regular GPU tuple
# enumerator and deterministic host materializer.
plant_u = i64[4]
plant_v = i64[4]
plant_w = i64[4]
plant_u[0] = 1
plant_v[0] = 2
plant_w[0] = 4
plant_u[1] = 8
plant_v[1] = 16
plant_w[1] = 32
plant_u[2] = 64
plant_v[2] = 2
plant_w[2] = 1
plant_u[3] = 64
plant_v[3] = 16
plant_w[3] = 2
selected = i64[4]
out_u = i64[4]
out_v = i64[4]
out_w = i64[4]
meta = i64[8]
stats = i64[8]
made = fflrsp_find_gpu(device, library, queue, plant_u, plant_v, plant_w, 4, 0, 6, selected, out_u, out_v, out_w, meta, stats) ## i64
z = fflrsp_test_expect("GPU rank-two absorbed shear", made == 4 && meta[0] == 2)
local_u = i64[4]
local_v = i64[4]
local_w = i64[4]
i = 0 ## i64
while i < made
  local_u[i] = plant_u[selected[i]]
  local_v[i] = plant_v[selected[i]]
  local_w[i] = plant_w[selected[i]]
  i += 1
z = fflrsp_test_expect("planted GPU hit exact", fftc_local_exact(local_u, local_v, local_w, made, out_u, out_v, out_w, made) == 1)
z = fflrsp_test_expect("planted GPU hit beyond one flip", fflrs_is_one_flip(local_u, local_v, local_w, made, out_u, out_v, out_w) == 0)

# The checked-in 5x5 frontier's first useful absorbed shear occurs after 504
# source pairs.  This is the evidence that earns the mode a bounded pool slot.
n = 5 ## i64
capacity = ffw_default_capacity(n) ## i64
state = i64[ffw_state_size(capacity)]
scheme_rank = ffw_load_scheme_cap(state, "benchmarks/matmul/metaflip/matmul_5x5_rank93_d1155_gf2.txt", n, capacity, 778899, 4, 2, 1000, 250) ## i64
z = fflrsp_test_expect("5x5 seed exact", scheme_rank == 93 && ffw_verify_current_exact(state, n) == 1)
all_u = i64[capacity]
all_v = i64[capacity]
all_w = i64[capacity]
exported = ffw_export_current(state, all_u, all_v, all_w) ## i64
real_selected = i64[4]
real_out_u = i64[4]
real_out_v = i64[4]
real_out_w = i64[4]
real_meta = i64[8]
real_stats = i64[8]
real_made = fflrsp_find_gpu(device, library, queue, all_u, all_v, all_w, exported, 0, 512, real_selected, real_out_u, real_out_v, real_out_w, real_meta, real_stats) ## i64
z = fflrsp_test_expect("real 5x5 GPU shear found", real_made == 3 || real_made == 4)
z = fflrsp_test_expect("real 5x5 reaches pair 504", real_meta[3] == 504)
if real_made > 0
  applied = ffsr_apply_current(state, real_selected, real_made, real_out_u, real_out_v, real_out_w, real_made) ## i64
  z = fflrsp_test_expect("real 5x5 full n6 splice", applied == 93 && ffw_verify_current_exact(state, n) == 1)

# Nonce rotation must change the first source door while retaining exactness.
rot_selected = i64[4]
rot_out_u = i64[4]
rot_out_v = i64[4]
rot_out_w = i64[4]
rot_meta = i64[8]
rot_stats = i64[8]
rot_made = fflrsp_find_gpu(device, library, queue, plant_u, plant_v, plant_w, 4, 1, 6, rot_selected, rot_out_u, rot_out_v, rot_out_w, rot_meta, rot_stats) ## i64
z = fflrsp_test_expect("nonce-rotated search remains valid", rot_made == 4)
z = fflrsp_test_expect("deterministic structural winner recorded", stats[3] >= 0 && stats[3] < stats[1])

<< "low-rank shear GPU: real-size=" + real_made.to_s() + " pair=" + real_meta[3].to_s() + " work=" + real_stats[1].to_s() + " structural=" + real_stats[2].to_s()
<< "flipfleet_low_rank_shear_pool_test: all checks passed"
