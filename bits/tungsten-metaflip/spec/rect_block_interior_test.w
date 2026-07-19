use ../lib/metaflip/strategies/rect_block_interior

failures = 0 ## i64

-> ffrbit_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL rectangular block interior: " + label
    return 1
  0

-> ffrbit_low_bit(value) (i64) i64
  bit = 1 ## i64
  while bit > 0 && (value & bit) == 0
    bit = bit << 1
  bit

n = 2 ## i64
m = 2 ## i64
p = 5 ## i64
capacity = 128 ## i64
dslack = 4 ## i64
cycles = 4 ## i64
workq = 1000 ## i64
wanderq = 250 ## i64
root = __DIR__ + "/../lib/metaflip/seeds/gf2/"
record_path = root + "matmul_2x2x5_rank18_d84_gf2.txt"

record = i64[ffr_state_size(capacity)]
record_rank = ffr_load_scheme_cap(record, record_path, n, m, p, capacity, 701, dslack, cycles, workq, wanderq) ## i64
failures += ffrbit_expect("record exact", record_rank == 18 && ffr_verify_best_exact(record, n, m, p) == 1)

source_u = i64[capacity]
source_v = i64[capacity]
source_w = i64[capacity]
exported = ffw_export_best(record, source_u, source_v, source_w) ## i64
plant_u = i64[capacity]
plant_v = i64[capacity]
plant_w = i64[capacity]
i = 0 ## i64
while i < exported
  plant_u[i] = source_u[i]
  plant_v[i] = source_v[i]
  plant_w[i] = source_w[i]
  i += 1

split_position = 0 - 1 ## i64
split_axis = 0 - 1 ## i64
i = 0
while i < exported && split_position < 0
  if ffw_popcount(plant_u[i]) > 1
    split_position = i
    split_axis = 0
  elsif ffw_popcount(plant_v[i]) > 1
    split_position = i
    split_axis = 1
  elsif ffw_popcount(plant_w[i]) > 1
    split_position = i
    split_axis = 2
  i += 1
failures += ffrbit_expect("record exposes a legal split", split_position >= 0)

if split_position >= 0
  plant_u[exported] = plant_u[split_position]
  plant_v[exported] = plant_v[split_position]
  plant_w[exported] = plant_w[split_position]
  factor = plant_u[split_position] ## i64
  if split_axis == 1
    factor = plant_v[split_position]
  if split_axis == 2
    factor = plant_w[split_position]
  part = ffrbit_low_bit(factor) ## i64
  rest = factor ^ part ## i64
  if split_axis == 0
    plant_u[split_position] = part
    plant_u[exported] = rest
  if split_axis == 1
    plant_v[split_position] = part
    plant_v[exported] = rest
  if split_axis == 2
    plant_w[split_position] = part
    plant_w[exported] = rest

planted = i64[ffr_state_size(capacity)]
planted_rank = ffr_init_terms_cap(planted, plant_u, plant_v, plant_w, exported + 1, n, m, p, capacity, 709, dslack, cycles, workq, wanderq) ## i64
failures += ffrbit_expect("planted +1 debt exact", planted_rank == 19 && ffr_verify_best_exact(planted, n, m, p) == 1)

stats = i64[7]
recovered = nil
attempt = 0 ## i64
start_ms = ccall("__w_clock_ms") ## i64
while attempt < 200 && recovered == nil
  candidate = ffrbi_try(planted, n, m, p, attempt, stats)
  if candidate != nil && ffr_best_rank(candidate) == 18
    recovered = candidate
  attempt += 1
elapsed_ms = ccall("__w_clock_ms") - start_ms ## i64

failures += ffrbit_expect("one call equals one scheduled attempt", stats[0] == attempt)
failures += ffrbit_expect("planted debt recovered", recovered != nil)
if recovered != nil
  failures += ffrbit_expect("recovered rank/density is exact", ffr_best_rank(recovered) == 18 && ffr_verify_best_exact(recovered, n, m, p) == 1)
failures += ffrbit_expect("source island was not mutated", ffr_best_rank(planted) == 19 && ffr_current_rank(planted) == 19 && ffr_verify_current_exact(planted, n, m, p) == 1)
failures += ffrbit_expect("accepted candidates are independently gated", stats[2] > 0 && stats[6] == 0)

failures += ffrbit_expect("natural rectangular cut", ffrbi_cut(5, 4, 2) == 3)
cut_seen = i64[4]
i = 1
while i < 17
  cut = ffrbi_cut(5, i, 1) ## i64
  if cut >= 1 && cut <= 4
    cut_seen[cut - 1] = 1
  i += 1
cut_total = 0 ## i64
i = 0
while i < cut_seen.size()
  cut_total += cut_seen[i]
  i += 1
failures += ffrbit_expect("off-center schedule covers every legal cut", cut_total == 4)
failures += ffrbit_expect("slow probe backs off by two", ffrbi_next_period(1, 201, 100) == 2)
failures += ffrbit_expect("fast probe returns gradually", ffrbi_next_period(8, 10, 100) == 4)
failures += ffrbit_expect("cadence is bounded", ffrbi_next_period(16, 1000, 1) == 16 && ffrbi_next_period(0, 0, 1) == 1)

if failures > 0
  exit(1)
<< "PASS rectangular block interior attempts=" + attempt.to_s() + " accepts=" + stats[2].to_s() + " drops=" + stats[3].to_s() + " elapsed_ms=" + elapsed_ms.to_s()
