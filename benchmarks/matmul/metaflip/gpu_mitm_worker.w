# Bounded Metal meet-in-the-middle worker for local rank surgery over GF(2).
#
# This checked-in instance is the 5x5 / 700-candidate default.  The companion
# gpu_mitm_surgery.py generator specializes DIM, POOL_MAX, TABLE_CAP, and the
# emitted .metal sidecar path for square tensors from 3x3 through 7x7.
#
# The two Metal passes deliberately avoid device atomics (not yet exposed by
# Tungsten's @gpu subset):
#   1. enumerate every unordered pair of 128-bit linear tensor fingerprints;
#   2. probe complementary pair fingerprints in a collision-preserving hash.
# Between them, the Tungsten host builds the open-addressed table from pass 1.
# Python independently checks full tensor signatures before accepting a hit.

## u32[]: fps0, fps1, fps2, fps3, pair0, pair1, pair2, pair3
## i32[]: enum_params
@gpu fn mitm_enumerate_pairs(fps0, fps1, fps2, fps3, pair0, pair1, pair2, pair3, enum_params)
  tid = gpu.thread_position_in_grid.x ## i32
  count = enum_params[0] ## i32
  left = tid / count ## i32
  right = tid - left * count ## i32
  if left < right
    pair0[tid] = fps0[left] ^ fps0[right]
    pair1[tid] = fps1[left] ^ fps1[right]
    pair2[tid] = fps2[left] ^ fps2[right]
    pair3[tid] = fps3[left] ^ fps3[right]

## u32[]: q0, q1, q2, q3, table0, table1, table2, table3, table_used, table_pair, target_fp, matches
## i32[]: probe_params
@gpu fn mitm_probe_pairs(q0, q1, q2, q3, table0, table1, table2, table3, table_used, table_pair, target_fp, matches, probe_params)
  tid = gpu.thread_position_in_grid.x ## i32
  count = probe_params[0] ## i32
  table_mask = probe_params[1] ## u32
  table_cap = probe_params[2] ## i32
  left = tid / count ## i32
  right = tid - left * count ## i32
  outbase = tid * 4 ## i32
  matches[outbase] = 0
  matches[outbase + 1] = 0
  matches[outbase + 2] = 0
  matches[outbase + 3] = 0
  if left < right
    want0 = target_fp[0] ^ q0[left] ^ q0[right] ## u32
    want1 = target_fp[1] ^ q1[left] ^ q1[right] ## u32
    want2 = target_fp[2] ^ q2[left] ^ q2[right] ## u32
    want3 = target_fp[3] ^ q3[left] ^ q3[right] ## u32
    mixed = want0 ^ (want1 >> 7) ^ (want2 >> 13) ^ (want3 >> 19) ## u32
    slot_u = mixed & table_mask ## u32
    slot = slot_u ## i32
    scanned = 0 ## i32
    found = 0 ## i32
    while scanned < table_cap
      if table_used[slot] == 0
        scanned = table_cap
      else
        if table0[slot] == want0
          if table1[slot] == want1
            if table2[slot] == want2
              if table3[slot] == want3
                packed_u = table_pair[slot] ## u32
                packed = packed_u ## i32
                other_left = packed / count ## i32
                other_right = packed - other_left * count ## i32
                if other_left != left
                  if other_left != right
                    if other_right != left
                      if other_right != right
                        if found < 4
                          matches[outbase + found] = packed_u
                          found = found + 1
        slot = (slot + 1) & table_mask
        scanned = scanned + 1

use core/metal

## u32[]: hp0, hp1, hp2, hp3, used, ht0, ht1, ht2, ht3, hpair
## i64: hcount, hcap, left, right, pair_index, p0, p1, p2, p3, mixed, slot
fn mitm_build_table(hp0, hp1, hp2, hp3, used, ht0, ht1, ht2, ht3, hpair, hcount, hcap)
  left = 0
  while left < hcount
    right = left + 1
    while right < hcount
      pair_index = left * hcount + right
      p0 = hp0[pair_index]
      p1 = hp1[pair_index]
      p2 = hp2[pair_index]
      p3 = hp3[pair_index]
      mixed = p0 ^ (p1 >> 7) ^ (p2 >> 13) ^ (p3 >> 19)
      slot = mixed & (hcap - 1)
      while used[slot] != 0
        slot = (slot + 1) & (hcap - 1)
      used[slot] = 1
      ht0[slot] = p0
      ht1[slot] = p1
      ht2[slot] = p2
      ht3[slot] = p3
      hpair[slot] = pair_index
      right += 1
    left += 1
  1

## u32[]: hm
## i64: mcount, mhits_per, ml, mr, mpi, mh, mpacked, mol, mor, mhits
fn mitm_emit_hits(hm, mcount, mhits_per)
  mhits = 0
  ml = 0
  while ml < mcount
    mr = ml + 1
    while mr < mcount
      mpi = ml * mcount + mr
      mh = 0
      while mh < mhits_per
        mpacked = hm[mpi * mhits_per + mh]
        if mpacked > 0
          mol = mpacked / mcount
          mor = mpacked - mol * mcount
          << "GPU_MITM_HIT " + ml.to_s() + " " + mr.to_s() + " " + mol.to_s() + " " + mor.to_s()
          mhits += 1
        mh += 1
      mr += 1
    ml += 1
  mhits

DIM = 5
POOL_MAX = 700
TABLE_CAP = 524288
HITS_PER_QUERY = 4

request_path = "/tmp/gpu_mitm_request.txt"
av = argv()
if av.size() > 0
  request_path = av[0]

lines = read_file(request_path).split("\n")
header = lines[0].split(" ")
count = header[0].to_i()
target0 = header[1].to_i()
target1 = header[2].to_i()
target2 = header[3].to_i()
target3 = header[4].to_i()
if count < 4 || count > POOL_MAX
  << "GPU_MITM_ERROR dimension=" + DIM.to_s() + " count=" + count.to_s() + " pool_max=" + POOL_MAX.to_s()
  exit(2)

host_fps0 = metal_array(32, POOL_MAX)
host_fps1 = metal_array(32, POOL_MAX)
host_fps2 = metal_array(32, POOL_MAX)
host_fps3 = metal_array(32, POOL_MAX)
i = 0
while i < count
  fields = lines[i + 1].split(" ")
  host_fps0[i] = fields[0].to_i()
  host_fps1[i] = fields[1].to_i()
  host_fps2[i] = fields[2].to_i()
  host_fps3[i] = fields[3].to_i()
  i += 1

msl = read_file("benchmarks/matmul/metaflip/gpu_mitm_worker.metal")
device = metal_device()
library = metal_compile_source(device, msl)
enum_pipeline = metal_pipeline(library, "mitm_enumerate_pairs")
probe_pipeline = metal_pipeline(library, "mitm_probe_pairs")
queue = metal_queue(device)

square = count * count
host_pair0 = metal_array(32, square)
host_pair1 = metal_array(32, square)
host_pair2 = metal_array(32, square)
host_pair3 = metal_array(32, square)
host_enum_params = metal_array(32, 1)
host_enum_params[0] = count
fps0_buf = metal_buffer_for(device, host_fps0)
fps1_buf = metal_buffer_for(device, host_fps1)
fps2_buf = metal_buffer_for(device, host_fps2)
fps3_buf = metal_buffer_for(device, host_fps3)
pair0_buf = metal_buffer_for(device, host_pair0)
pair1_buf = metal_buffer_for(device, host_pair1)
pair2_buf = metal_buffer_for(device, host_pair2)
pair3_buf = metal_buffer_for(device, host_pair3)
enum_params_buf = metal_buffer_for(device, host_enum_params)

t0 = ccall("__w_clock_ms")
metal_dispatch_n(queue, enum_pipeline, [fps0_buf, fps1_buf, fps2_buf, fps3_buf, pair0_buf, pair1_buf, pair2_buf, pair3_buf, enum_params_buf], square)
t1 = ccall("__w_clock_ms")

# Build a load <= 1/2 linear-probe table on the host.  Every pair occupies its
# own slot, including equal fingerprints, so the GPU probe can continue past a
# colliding representative until it finds a disjoint pair.
host_used = metal_array(32, TABLE_CAP)
host_table0 = metal_array(32, TABLE_CAP)
host_table1 = metal_array(32, TABLE_CAP)
host_table2 = metal_array(32, TABLE_CAP)
host_table3 = metal_array(32, TABLE_CAP)
host_table_pair = metal_array(32, TABLE_CAP)
pairs = count * (count - 1) / 2
active_cap = 1
while active_cap < pairs * 2
  active_cap *= 2
mitm_build_table(host_pair0, host_pair1, host_pair2, host_pair3, host_used, host_table0, host_table1, host_table2, host_table3, host_table_pair, count, active_cap)
t2 = ccall("__w_clock_ms")

host_target = metal_array(32, 4)
host_target[0] = target0
host_target[1] = target1
host_target[2] = target2
host_target[3] = target3
host_matches = metal_array(32, square * HITS_PER_QUERY)
host_probe_params = metal_array(32, 3)
host_probe_params[0] = count
host_probe_params[1] = active_cap - 1
host_probe_params[2] = active_cap
table0_buf = metal_buffer_for(device, host_table0)
table1_buf = metal_buffer_for(device, host_table1)
table2_buf = metal_buffer_for(device, host_table2)
table3_buf = metal_buffer_for(device, host_table3)
table_used_buf = metal_buffer_for(device, host_used)
table_pair_buf = metal_buffer_for(device, host_table_pair)
target_buf = metal_buffer_for(device, host_target)
matches_buf = metal_buffer_for(device, host_matches)
probe_params_buf = metal_buffer_for(device, host_probe_params)

t3 = ccall("__w_clock_ms")
metal_dispatch_n(queue, probe_pipeline, [fps0_buf, fps1_buf, fps2_buf, fps3_buf, table0_buf, table1_buf, table2_buf, table3_buf, table_used_buf, table_pair_buf, target_buf, matches_buf, probe_params_buf], square)
t4 = ccall("__w_clock_ms")

hits = mitm_emit_hits(host_matches, count, HITS_PER_QUERY)

<< "GPU_MITM_RESULT dimension=" + DIM.to_s() + " candidates=" + count.to_s() + " pairs=" + pairs.to_s() + " table=" + active_cap.to_s() + " enum_ms=" + (t1 - t0).to_s() + " table_ms=" + (t2 - t1).to_s() + " upload_ms=" + (t3 - t2).to_s() + " probe_ms=" + (t4 - t3).to_s() + " fingerprint_hits=" + hits.to_s()
