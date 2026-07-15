use metaflip_worker
use flipfleet_frozen_fringe_sat

n = 4 ## i64
cap = ffw_default_capacity(n) ## i64
size = ffw_state_size(cap) ## i64
frontier = i64[size]
rank = ffw_load_scheme_cap(frontier, "benchmarks/matmul/metaflip/matmul_4x4_rank47_d450_gf2.txt", n, cap, 5001, 0, 1, 1, 1) ## i64
if rank != 47 || ffw_verify_current_exact(frontier, n) == 0
  << "4x4 frontier load failed"
  exit(1)

trials = 128 ## i64
mode = 0 ## i64
while mode < 2
  total_cells = 0 ## i64
  min_cells = 999999999 ## i64
  max_cells = 0 ## i64
  min_vars = 999999999 ## i64
  below_2048 = 0 ## i64
  started = ccall("__w_clock_ms") ## i64
  trial = 0 ## i64
  while trial < trials
    selected = i64[16]
    if fffsat_select(frontier, 16, 7001 + trial * 131, mode, selected) != 16
      exit(1)
    dimensions = i64[8]
    if fffsat_query_dimensions(frontier, selected, 16, 15, dimensions) != 1
      exit(1)
    cells = dimensions[3] ## i64
    total_cells += cells
    if cells < min_cells
      min_cells = cells
    if cells > max_cells
      max_cells = cells
    if dimensions[4] < min_vars
      min_vars = dimensions[4]
    if cells <= 2048
      below_2048 += 1
    trial += 1
  elapsed = ccall("__w_clock_ms") - started ## i64
  label = "uniform" ## String
  if mode == 1
    label = "clustered"
  << label + " trials=" + trials.to_s() + " selection+size-ms=" + elapsed.to_s() + " cells-min/avg/max=" + min_cells.to_s() + "/" + (total_cells / trials).to_s() + "/" + max_cells.to_s() + " min-vars=" + min_vars.to_s() + " cells<=2048=" + below_2048.to_s()
  mode += 1
