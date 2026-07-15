use flipfleet_circuit_image_search

-> ffcist_expect(label, condition) (String bool) i64
  if !condition
    << "CIRCUIT_IMAGE_SEARCH_FAIL " + label
    exit(1)
  1

# Two live anchors from a primitive template must recover an exact +1-or-
# better complementary endpoint without assuming a matrix-multiplication seed.
template_u = i64[12]
template_v = i64[12]
template_w = i64[12]
count = ffc_template_fill(0, template_u, template_v, template_w) ## i64
ffcis_source_u = i64[2]
ffcis_source_v = i64[2]
ffcis_source_w = i64[2]
ffcis_source_u[0] = template_u[0]
ffcis_source_v[0] = template_v[0]
ffcis_source_w[0] = template_w[0]
ffcis_source_u[1] = template_u[3]
ffcis_source_v[1] = template_v[3]
ffcis_source_w[1] = template_w[3]
out_u = i64[12]
out_v = i64[12]
out_w = i64[12]
meta = i64[13]
found = ffcis_search_pairs(ffcis_source_u, ffcis_source_v, ffcis_source_w, 2, 0, out_u, out_v, out_w, meta) ## i64
ffcist_expect("found", found == 5 && meta[8] <= 1 && meta[11] >= 2)
ffcist_expect("primitive", ffc_is_primitive_circuit(out_u, out_v, out_w, found) == 1)
<< "flipfleet_circuit_image_search_test: all checks passed delta=" + meta[8].to_s() + " overlap=" + meta[11].to_s()
