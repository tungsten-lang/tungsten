# Backpressure bounds pending composition recipes, not retained disk bytes.
# Inputs keep their durable source tickets while expansion waits for capacity.
use ../composition/worker

-> ffrf_composition_limit() i64
  ffbc_composition_limit()

# Source + matrix + six basis images + two complete coordinate sweeps;
# each parent produces at most three axes times three scales. Duplicates
# reduce this reservation. Enforce the bound again before composition intake.
-> ffrf_composition_reserve(n, m, p) (i64 i64 i64) i64
  if ffrf_shape_valid(n, m, p) != 1
    return 0
  coordinates = 0 ## i64
  if n > 1
    coordinates += n
  if m > 1
    coordinates += m
  if p > 1
    coordinates += p
  9*(8+2*coordinates)

-> ffrf_budget_request(root, meta) (String i64[]) i64
  meta[0] = 0
  meta[1] = 0
  raw = File.read_prefix(root + "/backpressure", 129)
  if raw == nil
    return 1
  fields = raw.strip().split(" ")
  if fields.size() != 3 || fields[0] != "MFR_PRESSURE1"
    return 0
  job = ffw_parse_decimal_i64(fields[1]) ## i64
  reserve = ffw_parse_decimal_i64(fields[2]) ## i64
  if job < 1 || job > 1000000000000 || reserve < 1 || reserve > 1269 || raw != "MFR_PRESSURE1 " + job.to_s() + " " + reserve.to_s() + "\n"
    return 0
  meta[0] = job
  meta[1] = reserve
  1

# Count the at-most-nine task records committed before their submitted cursor
# during a previous interrupted parent intake. They already occupy capacity.
-> ffrf_budget_begin(root, job, reserve) (String i64 i64) i64
  if reserve < 1 || reserve > 1269
    return 0
  if ffmd_recover(root) != 1
    return 0
  limit = ffrf_composition_limit() ## i64
  if limit == 0
    return 1
  pending = ffmd_occupancy(root) ## i64
  if pending < 0
    return 0
  if pending+reserve <= limit
    return 1
  body = "MFR_PRESSURE1 " + job.to_s() + " " + reserve.to_s() + "\n"
  if ffrf_atomic(root + "/backpressure", body, "composition") != 1
    return 0
  0-3
