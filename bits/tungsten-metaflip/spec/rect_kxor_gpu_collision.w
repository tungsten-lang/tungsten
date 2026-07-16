# Regression for collision-complete rectangular k-XOR probing.
#
# Every synthetic candidate has the same 128-bit fingerprint, so one query
# sees all C(6,3)=20 disjoint table triples.  GPU chain order is deliberately
# unspecified.  After reading ordinals zero and one, construct local tensors
# for which ordinal zero is a false fingerprint hit and ordinal one is exact.
# This proves that a failed first local gate cannot hide a later exact tuple.

use ../lib/metaflip/kernels/rect_kxor
use core/system

-> ffrxct_fail(label) (String) i64
  << "FAIL rectangular kxor GPU collision: " + label
  exit(1)
  0

metal_path = System.executable_path() + ".metal"
device = metal_device()
msl = read_file(metal_path)
if msl == nil || msl.size() == 0
  z = ffrxct_fail("generated Metal source")
library = metal_compile_source(device, msl)
queue = metal_queue(device)

count = 9 ## i64
entries = count * (count - 1) * (count - 2) / 6 ## i64
hcap = 1 ## i64
while hcap < entries * 3
  hcap *= 2
fps0 = metal_array(32, count)
fps1 = metal_array(32, count)
fps2 = metal_array(32, count)
fps3 = metal_array(32, count)
target = metal_array(32, 4)
heads = metal_array(32, hcap)
links = metal_array(32, entries)
build_params = metal_array(32, 3)
matches = metal_array(32, entries)
match_counts = metal_array(32, entries)
probe_params = metal_array(32, 4)
clear_pipeline = metal_pipeline(library, "ffrx_clear_chain_heads")
build_pipeline = metal_pipeline(library, "ffrx_build_canonical_tuple_chains")
probe_pipeline = metal_pipeline(library, "ffrx_probe_canonical_triples")
compact_pipeline = metal_pipeline(library, "ffrx_compact_match_counts")
active_queries = metal_array(32, entries)
match_summary = metal_array(32, 1)

build_params[0] = count
build_params[1] = 3
build_params[2] = hcap - 1
metal_dispatch_n(queue, clear_pipeline, [metal_buffer_for(device, heads)], hcap)
metal_dispatch_n(queue, build_pipeline, [metal_buffer_for(device, fps0), metal_buffer_for(device, fps1), metal_buffer_for(device, fps2), metal_buffer_for(device, fps3), metal_buffer_for(device, heads), metal_buffer_for(device, links), metal_buffer_for(device, build_params)], entries)

probe_params[0] = count
probe_params[1] = hcap - 1
probe_params[2] = 3
probe_params[3] = 0
metal_dispatch_n(queue, probe_pipeline, [metal_buffer_for(device, fps0), metal_buffer_for(device, fps1), metal_buffer_for(device, fps2), metal_buffer_for(device, fps3), metal_buffer_for(device, heads), metal_buffer_for(device, links), metal_buffer_for(device, target), metal_buffer_for(device, matches), metal_buffer_for(device, match_counts), metal_buffer_for(device, probe_params)], entries)
match_summary[0] = 0
metal_dispatch_n(queue, compact_pipeline, [metal_buffer_for(device, match_counts), metal_buffer_for(device, active_queries), metal_buffer_for(device, match_summary)], entries)

query_index = 0 ## i64
if match_counts[query_index] != 20
  z = ffrxct_fail("expected 20 disjoint same-fingerprint triples, got " + match_counts[query_index].to_s())
if match_summary[0] != entries
  z = ffrxct_fail("sparse summary active=" + match_summary[0].to_s())
compact_seen = i64[entries]
compact_hits = 0 ## i64
i = 0 ## i64
while i < match_summary[0]
  compact_query = active_queries[i] ## i64
  if compact_query < 0 || compact_query >= entries || compact_seen[compact_query] != 0
    z = ffrxct_fail("invalid compact query row=" + compact_query.to_s())
  compact_seen[compact_query] = 1
  compact_hits += match_counts[compact_query]
  i += 1
if compact_hits != entries * 20
  z = ffrxct_fail("sparse summary hits=" + compact_hits.to_s())
first_index = matches[query_index] - 1 ## i64
if first_index < 0
  z = ffrxct_fail("ordinal zero")

probe_params[3] = 1
metal_dispatch_n(queue, probe_pipeline, [metal_buffer_for(device, fps0), metal_buffer_for(device, fps1), metal_buffer_for(device, fps2), metal_buffer_for(device, fps3), metal_buffer_for(device, heads), metal_buffer_for(device, links), metal_buffer_for(device, target), metal_buffer_for(device, matches), metal_buffer_for(device, match_counts), metal_buffer_for(device, probe_params)], entries)
second_index = matches[query_index] - 1 ## i64
if second_index < 0 || second_index == first_index
  z = ffrxct_fail("ordinal one")

query = i64[3]
first_table = i64[3]
second_table = i64[3]
z = ffrx_unrank_triple(query_index, count, query)
z = ffrx_unrank_triple(first_index, count, first_table)
z = ffrx_unrank_triple(second_index, count, second_table)

# Give every candidate a distinct V coordinate.  The second replacement is
# then represented by seven selected terms by splitting one two-bit U factor;
# any different table triple necessarily changes the exact local tensor.
cu = i64[count]
cv = i64[count]
cw = i64[count]
i = 0 ## i64
while i < count
  cu[i] = 1
  cv[i] = 1 << i
  cw[i] = 1
  i += 1
split_candidate = second_table[0] ## i64
cu[split_candidate] = 3

first_replacement = i64[6]
second_replacement = i64[6]
i = 0
while i < 3
  first_replacement[i] = first_table[i]
  second_replacement[i] = second_table[i]
  first_replacement[i + 3] = query[i]
  second_replacement[i + 3] = query[i]
  i += 1

us = i64[7]
vs = i64[7]
ws = i64[7]
us[0] = 1
vs[0] = cv[split_candidate]
ws[0] = 1
us[1] = 2
vs[1] = cv[split_candidate]
ws[1] = 1
selected_count = 2 ## i64
i = 0
while i < 6
  source = second_replacement[i] ## i64
  if source != split_candidate
    us[selected_count] = cu[source]
    vs[selected_count] = cv[source]
    ws[selected_count] = cw[source]
    selected_count += 1
  i += 1
if selected_count != 7
  z = ffrxct_fail("selected split construction")
selected = i64[7]
i = 0
while i < 7
  selected[i] = i
  i += 1

if ffrx_local_exact_shape(us, vs, ws, selected, 7, cu, cv, cw, first_replacement, 6, 4, 9, 1) != 0
  z = ffrxct_fail("ordinal zero should fail the local gate")
if ffrx_local_exact_shape(us, vs, ws, selected, 7, cu, cv, cw, second_replacement, 6, 4, 9, 1) != 1
  z = ffrxct_fail("ordinal one should pass the local gate")

# Repeat the adversarial collision test for the direct 6 -> 4 pair/pair
# engine. One pair query has C(6,2)=15 disjoint table pairs; ordinal zero is
# made locally false and ordinal one is represented by splitting two of its
# four replacement terms into six selected terms.
pair_count = 8 ## i64
pair_entries = pair_count * (pair_count - 1) / 2 ## i64
pair_hcap = 1 ## i64
while pair_hcap < pair_entries * 3
  pair_hcap *= 2
pair_fps0 = metal_array(32, pair_count)
pair_fps1 = metal_array(32, pair_count)
pair_fps2 = metal_array(32, pair_count)
pair_fps3 = metal_array(32, pair_count)
pair_target = metal_array(32, 4)
pair_heads = metal_array(32, pair_hcap)
pair_links = metal_array(32, pair_entries)
pair_build_params = metal_array(32, 3)
pair_matches = metal_array(32, pair_entries)
pair_match_counts = metal_array(32, pair_entries)
pair_probe_params = metal_array(32, 4)
pair_probe_pipeline = metal_pipeline(library, "ffrx_probe_canonical_pairs")
pair_build_params[0] = pair_count
pair_build_params[1] = 2
pair_build_params[2] = pair_hcap - 1
metal_dispatch_n(queue, clear_pipeline, [metal_buffer_for(device, pair_heads)], pair_hcap)
metal_dispatch_n(queue, build_pipeline, [metal_buffer_for(device, pair_fps0), metal_buffer_for(device, pair_fps1), metal_buffer_for(device, pair_fps2), metal_buffer_for(device, pair_fps3), metal_buffer_for(device, pair_heads), metal_buffer_for(device, pair_links), metal_buffer_for(device, pair_build_params)], pair_entries)
pair_probe_params[0] = pair_count
pair_probe_params[1] = pair_hcap - 1
pair_probe_params[2] = 2
pair_probe_params[3] = 0
metal_dispatch_n(queue, pair_probe_pipeline, [metal_buffer_for(device, pair_fps0), metal_buffer_for(device, pair_fps1), metal_buffer_for(device, pair_fps2), metal_buffer_for(device, pair_fps3), metal_buffer_for(device, pair_heads), metal_buffer_for(device, pair_links), metal_buffer_for(device, pair_target), metal_buffer_for(device, pair_matches), metal_buffer_for(device, pair_match_counts), metal_buffer_for(device, pair_probe_params)], pair_entries)
pair_query_index = 0 ## i64
if pair_match_counts[pair_query_index] != 15
  z = ffrxct_fail("expected 15 disjoint same-fingerprint pairs, got " + pair_match_counts[pair_query_index].to_s())
pair_matches_count = pair_match_counts[pair_query_index] ## i64
pair_first_index = pair_matches[pair_query_index] - 1 ## i64
if pair_first_index < 0
  z = ffrxct_fail("pair ordinal zero")
pair_probe_params[3] = 1
metal_dispatch_n(queue, pair_probe_pipeline, [metal_buffer_for(device, pair_fps0), metal_buffer_for(device, pair_fps1), metal_buffer_for(device, pair_fps2), metal_buffer_for(device, pair_fps3), metal_buffer_for(device, pair_heads), metal_buffer_for(device, pair_links), metal_buffer_for(device, pair_target), metal_buffer_for(device, pair_matches), metal_buffer_for(device, pair_match_counts), metal_buffer_for(device, pair_probe_params)], pair_entries)
pair_second_index = pair_matches[pair_query_index] - 1 ## i64
if pair_second_index < 0 || pair_second_index == pair_first_index
  z = ffrxct_fail("pair ordinal one")

pair_query = i64[2]
pair_first_table = i64[2]
pair_second_table = i64[2]
z = ffrx_unrank_pair(pair_query_index, pair_count, pair_query)
z = ffrx_unrank_pair(pair_first_index, pair_count, pair_first_table)
z = ffrx_unrank_pair(pair_second_index, pair_count, pair_second_table)
pair_cu = i64[pair_count]
pair_cv = i64[pair_count]
pair_cw = i64[pair_count]
i = 0
while i < pair_count
  pair_cu[i] = 1
  pair_cv[i] = 1 << i
  pair_cw[i] = 1
  i += 1
pair_cu[pair_second_table[0]] = 3
pair_cu[pair_second_table[1]] = 3
pair_us = i64[6]
pair_vs = i64[6]
pair_ws = i64[6]
i = 0
while i < 2
  source = pair_second_table[i] ## i64
  pair_us[i*2] = 1
  pair_vs[i*2] = pair_cv[source]
  pair_ws[i*2] = 1
  pair_us[i*2+1] = 2
  pair_vs[i*2+1] = pair_cv[source]
  pair_ws[i*2+1] = 1
  i += 1
i = 0
while i < 2
  source = pair_query[i]
  pair_us[4+i] = pair_cu[source]
  pair_vs[4+i] = pair_cv[source]
  pair_ws[4+i] = pair_cw[source]
  i += 1
pair_selected = i64[6]
i = 0
while i < 6
  pair_selected[i] = i
  i += 1
pair_first_replacement = i64[4]
pair_second_replacement = i64[4]
i = 0
while i < 2
  pair_first_replacement[i] = pair_first_table[i]
  pair_second_replacement[i] = pair_second_table[i]
  pair_first_replacement[i+2] = pair_query[i]
  pair_second_replacement[i+2] = pair_query[i]
  i += 1
if ffrx_local_exact_shape(pair_us, pair_vs, pair_ws, pair_selected, 6, pair_cu, pair_cv, pair_cw, pair_first_replacement, 4, 4, 8, 1) != 0
  z = ffrxct_fail("pair ordinal zero should fail the local gate")
if ffrx_local_exact_shape(pair_us, pair_vs, pair_ws, pair_selected, 6, pair_cu, pair_cv, pair_cw, pair_second_replacement, 4, 4, 8, 1) != 1
  z = ffrxct_fail("pair ordinal one should pass the local gate")

# Finally exercise the 5 -> 3 single/pair join. The same pair query has six
# disjoint single-table matches. Split the accepted table term and one query
# term to represent ordinal one by five selected terms.
metal_dispatch_n(queue, clear_pipeline, [metal_buffer_for(device, pair_heads)], pair_hcap)
pair_build_params[0] = pair_count
pair_build_params[1] = 1
pair_build_params[2] = pair_hcap - 1
metal_dispatch_n(queue, build_pipeline, [metal_buffer_for(device, pair_fps0), metal_buffer_for(device, pair_fps1), metal_buffer_for(device, pair_fps2), metal_buffer_for(device, pair_fps3), metal_buffer_for(device, pair_heads), metal_buffer_for(device, pair_links), metal_buffer_for(device, pair_build_params)], pair_count)
pair_probe_params[2] = 1
pair_probe_params[3] = 0
metal_dispatch_n(queue, pair_probe_pipeline, [metal_buffer_for(device, pair_fps0), metal_buffer_for(device, pair_fps1), metal_buffer_for(device, pair_fps2), metal_buffer_for(device, pair_fps3), metal_buffer_for(device, pair_heads), metal_buffer_for(device, pair_links), metal_buffer_for(device, pair_target), metal_buffer_for(device, pair_matches), metal_buffer_for(device, pair_match_counts), metal_buffer_for(device, pair_probe_params)], pair_entries)
single_matches = pair_match_counts[pair_query_index] ## i64
if single_matches != 6
  z = ffrxct_fail("expected 6 disjoint same-fingerprint singles, got " + single_matches.to_s())
single_first = pair_matches[pair_query_index] - 1 ## i64
if single_first < 0
  z = ffrxct_fail("single ordinal zero")
pair_probe_params[3] = 1
metal_dispatch_n(queue, pair_probe_pipeline, [metal_buffer_for(device, pair_fps0), metal_buffer_for(device, pair_fps1), metal_buffer_for(device, pair_fps2), metal_buffer_for(device, pair_fps3), metal_buffer_for(device, pair_heads), metal_buffer_for(device, pair_links), metal_buffer_for(device, pair_target), metal_buffer_for(device, pair_matches), metal_buffer_for(device, pair_match_counts), metal_buffer_for(device, pair_probe_params)], pair_entries)
single_second = pair_matches[pair_query_index] - 1 ## i64
if single_second < 0 || single_second == single_first
  z = ffrxct_fail("single ordinal one")

single_cu = i64[pair_count]
single_cv = i64[pair_count]
single_cw = i64[pair_count]
i = 0
while i < pair_count
  single_cu[i] = 1
  single_cv[i] = 1 << i
  single_cw[i] = 1
  i += 1
single_cu[single_second] = 3
single_cu[pair_query[0]] = 3
single_us = i64[5]
single_vs = i64[5]
single_ws = i64[5]
single_us[0] = 1
single_vs[0] = single_cv[single_second]
single_ws[0] = 1
single_us[1] = 2
single_vs[1] = single_cv[single_second]
single_ws[1] = 1
single_us[2] = 1
single_vs[2] = single_cv[pair_query[0]]
single_ws[2] = 1
single_us[3] = 2
single_vs[3] = single_cv[pair_query[0]]
single_ws[3] = 1
single_us[4] = single_cu[pair_query[1]]
single_vs[4] = single_cv[pair_query[1]]
single_ws[4] = single_cw[pair_query[1]]
single_selected = i64[5]
i = 0
while i < 5
  single_selected[i] = i
  i += 1
single_first_replacement = i64[3]
single_second_replacement = i64[3]
single_first_replacement[0] = single_first
single_second_replacement[0] = single_second
single_first_replacement[1] = pair_query[0]
single_second_replacement[1] = pair_query[0]
single_first_replacement[2] = pair_query[1]
single_second_replacement[2] = pair_query[1]
if ffrx_local_exact_shape(single_us, single_vs, single_ws, single_selected, 5, single_cu, single_cv, single_cw, single_first_replacement, 3, 4, 8, 1) != 0
  z = ffrxct_fail("single ordinal zero should fail the local gate")
if ffrx_local_exact_shape(single_us, single_vs, single_ws, single_selected, 5, single_cu, single_cv, single_cw, single_second_replacement, 3, 4, 8, 1) != 1
  z = ffrxct_fail("single ordinal one should pass the local gate")

<< "PASS rectangular kxor collision-complete ordinal fallback triple_matches=" + match_counts[query_index].to_s() + " pair_matches=" + pair_matches_count.to_s() + " single_matches=" + single_matches.to_s()
