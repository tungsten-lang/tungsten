use flipfleet_circuit_image_search3

-> ffcis3t_expect(label, condition) (String bool) i64
  if !condition
    << "CIRCUIT_IMAGE_SEARCH3_FAIL " + label
    exit(1)
  1

-> ffcis3t_same_tensor(left_u, left_v, left_w, left_count, right_u, right_v, right_w, right_count) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  width_u = ffc_max_width(left_u, left_count) ## i64
  candidate = ffc_max_width(right_u, right_count) ## i64
  if candidate > width_u
    width_u = candidate
  width_v = ffc_max_width(left_v, left_count) ## i64
  candidate = ffc_max_width(right_v, right_count)
  if candidate > width_v
    width_v = candidate
  width_w = ffc_max_width(left_w, left_count) ## i64
  candidate = ffc_max_width(right_w, right_count)
  if candidate > width_w
    width_w = candidate
  ui = 0 ## i64
  while ui < width_u
    vi = 0 ## i64
    while vi < width_v
      wi = 0 ## i64
      while wi < width_w
        parity = 0 ## i64
        term = 0 ## i64
        while term < left_count
          if ((left_u[term] >> ui) & 1) != 0 && ((left_v[term] >> vi) & 1) != 0 && ((left_w[term] >> wi) & 1) != 0
            parity = parity ^ 1
          term += 1
        term = 0
        while term < right_count
          if ((right_u[term] >> ui) & 1) != 0 && ((right_v[term] >> vi) & 1) != 0 && ((right_w[term] >> wi) & 1) != 0
            parity = parity ^ 1
          term += 1
        if parity != 0
          return 0
        wi += 1
      vi += 1
    ui += 1
  1

# The axis solver must recover a deliberately non-coordinate injective map.
maps = i64[9]
ok = ffcis3_fit_axis(3, 5, 7, 273, 138, 410, maps, 0) ## i64
z = ffcis3t_expect("axis fit", ok == 1)
z = ffcis3t_expect("axis image 0", ffc_apply_linear_map(3, maps, 0, 3) == 273)
z = ffcis3t_expect("axis image 1", ffc_apply_linear_map(5, maps, 0, 3) == 138)
z = ffcis3t_expect("axis image 2", ffc_apply_linear_map(7, maps, 0, 3) == 410)
z = ffcis3t_expect("dependent destination rejected", ffcis3_fit_axis(3, 5, 7, 1, 2, 3, maps, 0) == 0)

# A complete primitive template as the source is the smallest planted mining
# control.  The three-anchor closure must find and annihilate all ten terms.
template_u = i64[12]
template_v = i64[12]
template_w = i64[12]
template_count = ffc_template_fill(5, template_u, template_v, template_w) ## i64
z = ffcis3t_expect("template ten", template_count == 10)
z = ffcis3t_expect("template primitive", ffc_is_primitive_circuit(template_u, template_v, template_w, template_count) == 1)
found_u = i64[12]
found_v = i64[12]
found_w = i64[12]
meta = i64[21]
found = ffcis3_search_triples(template_u, template_v, template_w, template_count, 0, 0, 0, found_u, found_v, found_w, meta) ## i64
z = ffcis3t_expect("anchor bank complete", meta[0] == 32)
z = ffcis3t_expect("planted relation found", found == 10 && meta[9] == 0 - 10 && meta[12] == 10)
z = ffcis3t_expect("retained relation exact", ffc_is_primitive_circuit(found_u, found_v, found_w, found) == 1 && meta[5] > 0)
empty_u = i64[24]
empty_v = i64[24]
empty_w = i64[24]
empty_rank = ffcis3_apply_circuit(template_u, template_v, template_w, template_count, found_u, found_v, found_w, found, empty_u, empty_v, empty_w) ## i64
z = ffcis3t_expect("planted annihilation", empty_rank == 0)

# A three-live / seven-added side of template 5 supplies the structural
# separation from the flattening-gauge worker.  The added side has 4/5/5
# distinct U/V/W factors, strictly more than k=3 on every axis; a direct
# k-term flattening-gauge transform can expose at most k transformed factors
# on its chosen flattening axis.
gauge_source_u = i64[3]
gauge_source_v = i64[3]
gauge_source_w = i64[3]
gauge_source_u[0] = template_u[0]
gauge_source_v[0] = template_v[0]
gauge_source_w[0] = template_w[0]
gauge_source_u[1] = template_u[4]
gauge_source_v[1] = template_v[4]
gauge_source_w[1] = template_w[4]
gauge_source_u[2] = template_u[6]
gauge_source_v[2] = template_v[6]
gauge_source_w[2] = template_w[6]
gauge_circuit_u = i64[12]
gauge_circuit_v = i64[12]
gauge_circuit_w = i64[12]
gauge_meta = i64[21]
gauge_count = ffcis3_search_triples(gauge_source_u, gauge_source_v, gauge_source_w, 3, 0, 0, 1, gauge_circuit_u, gauge_circuit_v, gauge_circuit_w, gauge_meta) ## i64
z = ffcis3t_expect("gauge-resistant circuit", gauge_count == 10 && gauge_meta[9] == 4 && gauge_meta[12] == 3 && gauge_meta[18] > 0 && gauge_meta[20] > 3)
gauge_out_u = i64[16]
gauge_out_v = i64[16]
gauge_out_w = i64[16]
gauge_out_rank = ffcis3_apply_circuit(gauge_source_u, gauge_source_v, gauge_source_w, 3, gauge_circuit_u, gauge_circuit_v, gauge_circuit_w, gauge_count, gauge_out_u, gauge_out_v, gauge_out_w) ## i64
z = ffcis3t_expect("gauge-resistant 3-to-7 exchange", gauge_out_rank == 7 && ffcis3t_same_tensor(gauge_source_u, gauge_source_v, gauge_source_w, 3, gauge_out_u, gauge_out_v, gauge_out_w, 7) == 1)

# Full n^6 gate: toggle a mapped ten-term zero circuit into the exact 3x3
# rank-23 scheme.  The shoulder remains exact at rank 33; the miner must find
# an exact ten-term tunnel back to rank 23, not merely a sketch collision.
n = 3 ## i64
capacity = ffw_default_capacity(n) ## i64
state_size = ffw_state_size(capacity) ## i64
base = i64[state_size]
base_rank = ffw_load_scheme_cap(base, "benchmarks/matmul/metaflip/matmul_3x3_rank23_d139_gf2.txt", n, capacity, 88301, 0, 1, 1, 1) ## i64
z = ffcis3t_expect("base exact", base_rank == 23 && ffw_verify_current_exact(base, n) == 1)
base_u = i64[capacity]
base_v = i64[capacity]
base_w = i64[capacity]
z = ffw_export_current(base, base_u, base_v, base_w)

image_maps = i64[9]
image_maps[0] = 273
image_maps[1] = 138
image_maps[2] = 84
image_maps[3] = 289
image_maps[4] = 146
image_maps[5] = 76
image_maps[6] = 321
image_maps[7] = 162
image_maps[8] = 100
circuit_u = i64[12]
circuit_v = i64[12]
circuit_w = i64[12]
circuit_meta = i64[9]
circuit_count = ffc_map_template(5, image_maps, circuit_u, circuit_v, circuit_w, circuit_meta) ## i64
z = ffcis3t_expect("mapped circuit", circuit_count == 10 && ffc_is_primitive_circuit(circuit_u, circuit_v, circuit_w, circuit_count) == 1)

shoulder_u = i64[capacity]
shoulder_v = i64[capacity]
shoulder_w = i64[capacity]
shoulder_rank = ffcis3_apply_circuit(base_u, base_v, base_w, base_rank, circuit_u, circuit_v, circuit_w, circuit_count, shoulder_u, shoulder_v, shoulder_w) ## i64
z = ffcis3t_expect("collision-free planted shoulder", shoulder_rank == 33)
shoulder = i64[state_size]
loaded_shoulder = ffw_init_terms_cap(shoulder, shoulder_u, shoulder_v, shoulder_w, shoulder_rank, n, capacity, 88303, 0, 1, 1, 1) ## i64
z = ffcis3t_expect("shoulder full gate", loaded_shoulder == shoulder_rank && ffw_verify_current_exact(shoulder, n) == 1)

return_circuit_u = i64[12]
return_circuit_v = i64[12]
return_circuit_w = i64[12]
return_meta = i64[21]
return_count = ffcis3_search_triples(shoulder_u, shoulder_v, shoulder_w, shoulder_rank, 0, 7, 0, return_circuit_u, return_circuit_v, return_circuit_w, return_meta) ## i64
z = ffcis3t_expect("full-gate tunnel found", return_count == 10 && return_meta[9] <= 0 - 10)
returned_u = i64[capacity]
returned_v = i64[capacity]
returned_w = i64[capacity]
returned_rank = ffcis3_apply_circuit(shoulder_u, shoulder_v, shoulder_w, shoulder_rank, return_circuit_u, return_circuit_v, return_circuit_w, return_count, returned_u, returned_v, returned_w) ## i64
returned = i64[state_size]
loaded_return = ffw_init_terms_cap(returned, returned_u, returned_v, returned_w, returned_rank, n, capacity, 88305, 0, 1, 1, 1) ## i64
z = ffcis3t_expect("returned full gate", returned_rank == 23 && loaded_return == 23 && ffw_verify_current_exact(returned, n) == 1)

<< "flipfleet_circuit_image_search3_test: all checks passed anchors=" + meta[0].to_s() + " planted_scored=" + meta[4].to_s() + " full_fits=" + return_meta[2].to_s() + " full_rank=" + returned_rank.to_s()
