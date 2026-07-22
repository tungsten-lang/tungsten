# Regression for collision-complete square k-XOR probing.
#
# All synthetic candidates have the same 128-bit fingerprint.  A query must
# therefore be able to request every disjoint table tuple by ordinal instead
# of stopping after the first hash match.  This is the failure mode that can
# otherwise hide an exact replacement behind a false fingerprint collision.

use ../lib/metaflip/kernels/kxor
use core/system

-> ffxct_expect(label, condition) (String bool) i64
  if condition == false
    << "FAIL square kxor GPU collision: " + label
    exit(1)
  0

metal_path = System.executable_path() + ".metal"
device = metal_device()
msl = read_file(metal_path)
z = ffxct_expect("generated Metal source", msl != nil && msl.size() > 0) ## i64
library = metal_compile_source(device, msl)
queue = metal_queue(device)

count = 9 ## i64
square = count * count ## i64
cube = square * count ## i64
fourth = cube * count ## i64
fps0 = metal_array(32, count)
fps1 = metal_array(32, count)
fps2 = metal_array(32, count)
fps3 = metal_array(32, count)
target = metal_array(32, 4)

# Pair-table / triple-query path used by 6 -> 5.
pair_entries = count * (count - 1) / 2 ## i64
pair_cap = 1 ## i64
while pair_cap < pair_entries * 3
  pair_cap *= 2
pair_table = metal_array(32, pair_cap * 6)
a = 0 ## i64
while a < count
  b = a + 1 ## i64
  while b < count
    z = ffx_insert(pair_table, pair_cap, 0, 0, 0, 0, a * count + b + 1)
    b += 1
  a += 1
triple_matches = metal_array(32, cube)
triple_params = metal_array(32, 5)
triple_params[0] = count
triple_params[1] = pair_cap - 1
triple_params[2] = pair_cap
triple_params[3] = 2
triple_pipeline = metal_pipeline(library, "ffx_probe_triples")
triple_query = count + 2 ## i64 # canonical query (0,1,2)
triple_params[4] = 0
metal_dispatch_n(queue, triple_pipeline, [metal_buffer_for(device, fps0), metal_buffer_for(device, fps1), metal_buffer_for(device, fps2), metal_buffer_for(device, fps3), metal_buffer_for(device, pair_table), metal_buffer_for(device, target), metal_buffer_for(device, triple_matches), metal_buffer_for(device, triple_params)], cube)
pair0 = triple_matches[triple_query] ## i64
triple_params[4] = 1
metal_dispatch_n(queue, triple_pipeline, [metal_buffer_for(device, fps0), metal_buffer_for(device, fps1), metal_buffer_for(device, fps2), metal_buffer_for(device, fps3), metal_buffer_for(device, pair_table), metal_buffer_for(device, target), metal_buffer_for(device, triple_matches), metal_buffer_for(device, triple_params)], cube)
pair1 = triple_matches[triple_query] ## i64
z = ffxct_expect("distinct pair ordinals", pair0 > 0 && pair1 > 0 && pair0 != pair1)
triple_params[4] = 14
metal_dispatch_n(queue, triple_pipeline, [metal_buffer_for(device, fps0), metal_buffer_for(device, fps1), metal_buffer_for(device, fps2), metal_buffer_for(device, fps3), metal_buffer_for(device, pair_table), metal_buffer_for(device, target), metal_buffer_for(device, triple_matches), metal_buffer_for(device, triple_params)], cube)
z = ffxct_expect("last of fifteen disjoint pairs", triple_matches[triple_query] > 0)
triple_params[4] = 15
metal_dispatch_n(queue, triple_pipeline, [metal_buffer_for(device, fps0), metal_buffer_for(device, fps1), metal_buffer_for(device, fps2), metal_buffer_for(device, fps3), metal_buffer_for(device, pair_table), metal_buffer_for(device, target), metal_buffer_for(device, triple_matches), metal_buffer_for(device, triple_params)], cube)
z = ffxct_expect("pair ordinal exhaustion", triple_matches[triple_query] == 0)

# Triple-table / quad-query path used by 8 -> 7.  Query (0,1,2,3) leaves five
# candidate indices, hence exactly C(5,3)=10 disjoint table triples.
triple_entries = count * (count - 1) * (count - 2) / 6 ## i64
triple_cap = 1 ## i64
while triple_cap < triple_entries * 3
  triple_cap *= 2
triple_table = metal_array(32, triple_cap * 6)
a = 0
while a < count
  b = a + 1
  while b < count
    c = b + 1 ## i64
    while c < count
      z = ffx_insert(triple_table, triple_cap, 0, 0, 0, 0, a * square + b * count + c + 1)
      c += 1
    b += 1
  a += 1
quad_matches = metal_array(32, fourth)
quad_params = metal_array(32, 5)
quad_params[0] = count
quad_params[1] = triple_cap - 1
quad_params[2] = triple_cap
quad_params[3] = 3
quad_pipeline = metal_pipeline(library, "ffx_probe_quads")
quad_query = square + count * 2 + 3 ## i64
quad_params[4] = 0
metal_dispatch_n(queue, quad_pipeline, [metal_buffer_for(device, fps0), metal_buffer_for(device, fps1), metal_buffer_for(device, fps2), metal_buffer_for(device, fps3), metal_buffer_for(device, triple_table), metal_buffer_for(device, target), metal_buffer_for(device, quad_matches), metal_buffer_for(device, quad_params)], fourth)
triple0 = quad_matches[quad_query] ## i64
quad_params[4] = 1
metal_dispatch_n(queue, quad_pipeline, [metal_buffer_for(device, fps0), metal_buffer_for(device, fps1), metal_buffer_for(device, fps2), metal_buffer_for(device, fps3), metal_buffer_for(device, triple_table), metal_buffer_for(device, target), metal_buffer_for(device, quad_matches), metal_buffer_for(device, quad_params)], fourth)
triple1 = quad_matches[quad_query] ## i64
z = ffxct_expect("distinct triple ordinals", triple0 > 0 && triple1 > 0 && triple0 != triple1)
quad_params[4] = 9
metal_dispatch_n(queue, quad_pipeline, [metal_buffer_for(device, fps0), metal_buffer_for(device, fps1), metal_buffer_for(device, fps2), metal_buffer_for(device, fps3), metal_buffer_for(device, triple_table), metal_buffer_for(device, target), metal_buffer_for(device, quad_matches), metal_buffer_for(device, quad_params)], fourth)
z = ffxct_expect("last of ten disjoint triples", quad_matches[quad_query] > 0)
quad_params[4] = 10
metal_dispatch_n(queue, quad_pipeline, [metal_buffer_for(device, fps0), metal_buffer_for(device, fps1), metal_buffer_for(device, fps2), metal_buffer_for(device, fps3), metal_buffer_for(device, triple_table), metal_buffer_for(device, target), metal_buffer_for(device, quad_matches), metal_buffer_for(device, quad_params)], fourth)
z = ffxct_expect("triple ordinal exhaustion", quad_matches[quad_query] == 0)

<< "PASS square kxor collision-complete ordinal fallback pairs=15 triples=10"
