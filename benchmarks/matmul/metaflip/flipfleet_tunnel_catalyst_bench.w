# Reproducible real-frontier audit for atomic tunnels and labeled catalysts.
# Fixed caps keep this suitable for regression/decision evidence rather than
# turning a test into an unbounded search campaign.

use flipfleet_tunnel_catalyst_search
use flipfleet_basin_identity

-> fftcb_splice_state(base_u, base_v, base_w, rank, selected, out_u, out_v, out_w, n, capacity, seed) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64 i64 i64)
  child_u = i64[capacity]
  child_v = i64[capacity]
  child_w = i64[capacity]
  z = fftc_copy_terms(base_u, base_v, base_w, rank, child_u, child_v, child_w) ## i64
  i = 0 ## i64
  while i < 3
    child_u[selected[i]] = out_u[i]
    child_v[selected[i]] = out_v[i]
    child_w[selected[i]] = out_w[i]
    i += 1
  child = i64[ffw_state_size(capacity)]
  loaded = ffw_init_terms_cap(child, child_u, child_v, child_w, rank, n, capacity, seed, 0, 1, 1, 1) ## i64
  if loaded != rank || ffw_verify_best_exact(child, n) != 1
    return nil
  child

-> fftcb_run(label, path_name, n, tunnel_triples, tunnel_nodes, catalyst_triples, catalyst_nodes) (String String i64 i64 i64 i64 i64) i64
  capacity = ffw_default_capacity(n) ## i64
  state = i64[ffw_state_size(capacity)]
  rank = ffw_load_scheme_cap(state, path_name, n, capacity, 88001 + n, 0, 1, 1, 1) ## i64
  if rank < 1 || ffw_verify_best_exact(state, n) != 1
    << "TUNNEL_BENCH tensor=" + label + " error=load"
    return 0 - 1
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  z = ffw_export_best(state, us, vs, ws) ## i64
  source_density = fftc_density(us, vs, ws, rank) ## i64
  source_id = ffbi_best_id(state) ## i64

  selected = i64[3]
  out_u = i64[3]
  out_v = i64[3]
  out_w = i64[3]
  tunnel_path = i64[3]
  tunnel_meta = i64[8]
  start = ccall("__w_clock_ms") ## i64
  tunnel_hit = fftcs_search_tunnels(us, vs, ws, rank, tunnel_triples, tunnel_nodes, selected, out_u, out_v, out_w, tunnel_path, tunnel_meta) ## i64
  tunnel_ms = ccall("__w_clock_ms") - start ## i64
  tunnel_exact = 0 ## i64
  tunnel_novel = 0 ## i64
  tunnel_density = 0 - 1 ## i64
  tunnel_span3 = 0 ## i64
  tunnel_one = 0 ## i64
  if tunnel_hit == 3
    local_u = i64[3]
    local_v = i64[3]
    local_w = i64[3]
    z = fftcs_capture3(us, vs, ws, selected[0], selected[1], selected[2], local_u, local_v, local_w)
    tunnel_span3 = fftcs_span3_duplicate(local_u, local_v, local_w, out_u, out_v, out_w)
    tunnel_one = fftcs_one_flip(local_u, local_v, local_w, out_u, out_v, out_w)
    child = fftcb_splice_state(us, vs, ws, rank, selected, out_u, out_v, out_w, n, capacity, 88101 + n)
    if child != nil
      tunnel_exact = 1
      tunnel_density = ffw_best_bits(child)
      if ffbi_best_id(child) != source_id
        tunnel_novel = 1
  << "TUNNEL_BENCH tensor=" + label + " rank=" + rank.to_s() + " density=" + source_density.to_s() + " hit=" + tunnel_hit.to_s() + " exact=" + tunnel_exact.to_s() + " endpoint_density=" + tunnel_density.to_s() + " canonical_novel=" + tunnel_novel.to_s() + " one_flip=" + tunnel_one.to_s() + " span3=" + tunnel_span3.to_s() + " triples=" + tunnel_meta[1].to_s() + " final_nodes=" + tunnel_meta[2].to_s() + " endpoints=" + tunnel_meta[3].to_s() + " endpoint_one=" + tunnel_meta[4].to_s() + " endpoint_span3=" + tunnel_meta[5].to_s() + " global=" + tunnel_meta[6].to_s() + " best_delta=" + tunnel_meta[7].to_s() + " ms=" + tunnel_ms.to_s()

  catalyst_selected = i64[3]
  catalyst = i64[3]
  catalyst_out_u = i64[3]
  catalyst_out_v = i64[3]
  catalyst_out_w = i64[3]
  catalyst_path = i64[4]
  catalyst_meta = i64[8]
  start = ccall("__w_clock_ms")
  catalyst_hit = fftcs_search_catalysts(us, vs, ws, rank, catalyst_triples, catalyst_nodes, catalyst_selected, catalyst, catalyst_out_u, catalyst_out_v, catalyst_out_w, catalyst_path, catalyst_meta) ## i64
  catalyst_ms = ccall("__w_clock_ms") - start ## i64
  catalyst_exact = 0 ## i64
  catalyst_novel = 0 ## i64
  catalyst_density = 0 - 1 ## i64
  catalyst_span3 = 0 ## i64
  if catalyst_hit == 3
    local_u = i64[3]
    local_v = i64[3]
    local_w = i64[3]
    z = fftcs_capture3(us, vs, ws, catalyst_selected[0], catalyst_selected[1], catalyst_selected[2], local_u, local_v, local_w)
    catalyst_span3 = fftcs_span3_duplicate(local_u, local_v, local_w, catalyst_out_u, catalyst_out_v, catalyst_out_w)
    child = fftcb_splice_state(us, vs, ws, rank, catalyst_selected, catalyst_out_u, catalyst_out_v, catalyst_out_w, n, capacity, 88201 + n)
    if child != nil
      catalyst_exact = 1
      catalyst_density = ffw_best_bits(child)
      if ffbi_best_id(child) != source_id
        catalyst_novel = 1
  << "CATALYST_BENCH tensor=" + label + " rank=" + rank.to_s() + " hit=" + catalyst_hit.to_s() + " exact=" + catalyst_exact.to_s() + " endpoint_density=" + catalyst_density.to_s() + " canonical_novel=" + catalyst_novel.to_s() + " span3=" + catalyst_span3.to_s() + " triples=" + catalyst_meta[0].to_s() + " catalysts=" + catalyst_meta[1].to_s() + " final_nodes=" + catalyst_meta[2].to_s() + " equal_labels=" + catalyst_meta[3].to_s() + " changed=" + catalyst_meta[4].to_s() + " one_flip=" + catalyst_meta[5].to_s() + " collisions=" + catalyst_meta[6].to_s() + " ms=" + catalyst_ms.to_s()

  deep_selected = i64[3]
  deep_catalyst = i64[3]
  deep_u = i64[3]
  deep_v = i64[3]
  deep_w = i64[3]
  deep_path = i64[6]
  deep_meta = i64[8]
  start = ccall("__w_clock_ms")
  deep_hit = fftcs_search_catalysts_beam(us, vs, ws, rank, catalyst_triples, 6, 256, 10000000, deep_selected, deep_catalyst, deep_u, deep_v, deep_w, deep_path, deep_meta) ## i64
  deep_ms = ccall("__w_clock_ms") - start ## i64
  deep_exact = 0 ## i64
  deep_novel = 0 ## i64
  deep_density = 0 - 1 ## i64
  deep_span3 = 0 ## i64
  if deep_hit == 3
    local_u = i64[3]
    local_v = i64[3]
    local_w = i64[3]
    z = fftcs_capture3(us, vs, ws, deep_selected[0], deep_selected[1], deep_selected[2], local_u, local_v, local_w)
    deep_span3 = fftcs_span3_duplicate(local_u, local_v, local_w, deep_u, deep_v, deep_w)
    child = fftcb_splice_state(us, vs, ws, rank, deep_selected, deep_u, deep_v, deep_w, n, capacity, 88301 + n)
    if child != nil
      deep_exact = 1
      deep_density = ffw_best_bits(child)
      if ffbi_best_id(child) != source_id
        deep_novel = 1
  << "CATALYST_DEEP_BENCH tensor=" + label + " depth=6 beam=256 hit=" + deep_hit.to_s() + " exact=" + deep_exact.to_s() + " endpoint_density=" + deep_density.to_s() + " canonical_novel=" + deep_novel.to_s() + " span3=" + deep_span3.to_s() + " triples=" + deep_meta[0].to_s() + " catalysts=" + deep_meta[1].to_s() + " edges=" + deep_meta[2].to_s() + " valid=" + deep_meta[3].to_s() + " admitted=" + deep_meta[4].to_s() + " equal_labels=" + deep_meta[5].to_s() + " changed=" + deep_meta[6].to_s() + " one_flip=" + deep_meta[7].to_s() + " ms=" + deep_ms.to_s()
  1

# The caps are intentionally equal across tensors; 5x5 therefore samples a
# smaller fraction of triples rather than silently receiving more compute.
z = fftcb_run("4x4", "benchmarks/matmul/metaflip/matmul_4x4_rank47_d450_gf2.txt", 4, 512, 2000000, 32, 3000000) ## i64
z = fftcb_run("5x5", "benchmarks/matmul/metaflip/matmul_5x5_rank93_d1155_gf2.txt", 5, 512, 2000000, 32, 3000000)
