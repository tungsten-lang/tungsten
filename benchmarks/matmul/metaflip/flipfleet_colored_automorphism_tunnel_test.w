use flipfleet_colored_automorphism_tunnel

-> ffcatt_expect(label, condition) (String bool) i64
  if !condition
    << "COLORED_AUTOMORPHISM_TUNNEL_FAIL " + label
    exit(1)
  1

-> ffcatt_toggle(us, vs, ws, rank, capacity, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  found = 0 - 1 ## i64
  i = 0 ## i64
  while i < rank && found < 0
    if us[i] == u && vs[i] == v && ws[i] == w
      found = i
    i += 1
  if found >= 0
    rank -= 1
    us[found] = us[rank]
    vs[found] = vs[rank]
    ws[found] = ws[rank]
    return rank
  if rank >= capacity
    return 0 - 1
  us[rank] = u
  vs[rank] = v
  ws[rank] = w
  rank + 1

-> ffcatt_find_column(workspace, columns, term, color) (FFCATWorkspace i64 i64 i64) i64
  column = 0 ## i64
  while column < columns
    if workspace.column_term()[column] == term && workspace.column_color()[column] == color
      return column
    column += 1
  0 - 1

n = 2 ## i64
capacity = ffw_default_capacity(n) ## i64
state = i64[ffw_state_size(capacity)]
rank = ffw_init_naive_cap(state, n, capacity, 90101, 0, 1, 1, 1) ## i64
ffcatt_expect("naive source", rank == 8 && ffw_verify_current_exact(state, n) == 1)
us = i64[capacity]
vs = i64[capacity]
ws = i64[capacity]
ffcatt_expect("naive export", ffw_export_current(state, us, vs, ws) == rank)

# These four terms form one zero circuit:
#   6 x (4+1) x 5 = (2+4) x 5 x 5.
# None belongs to the naive M_2 support, so toggling all four adds a clean
# planted shoulder.  Colour the first two terms with g=swap(I0,I1), and the
# second two with h=swap(K0,K1).  Both colour syndromes are nonzero, but the
# images collide pairwise and cancel.  The exact coloured endpoint therefore
# removes the entire shoulder (rank 12 -> 8) without any exact binary stage.
rank = ffcatt_toggle(us, vs, ws, rank, capacity, 6, 4, 5)
rank = ffcatt_toggle(us, vs, ws, rank, capacity, 2, 5, 5)
rank = ffcatt_toggle(us, vs, ws, rank, capacity, 6, 1, 5)
rank = ffcatt_toggle(us, vs, ws, rank, capacity, 4, 5, 5)
ffcatt_expect("planted rank", rank == 12)
planted = i64[ffw_state_size(capacity)]
loaded = ffw_init_terms_cap(planted, us, vs, ws, rank, n, capacity, 90103, 0, 1, 1, 1) ## i64
ffcatt_expect("planted exact", loaded == rank && ffw_verify_current_exact(planted, n) == 1)

g = i64[4]
h = i64[4]
g[0] = 0
g[1] = 0
g[2] = 0
g[3] = 1
h[0] = 0
h[1] = 1
h[2] = 0
h[3] = 1
workspace = FFCATWorkspace.new(rank, n, capacity)
columns = ffcat_build_columns(us, vs, ws, rank, n, g, h, workspace) ## i64
ffcatt_expect("columns", columns > 0)

gadget_u = i64[4]
gadget_v = i64[4]
gadget_w = i64[4]
gadget_u[0] = 6
gadget_v[0] = 4
gadget_w[0] = 5
gadget_u[1] = 2
gadget_v[1] = 5
gadget_w[1] = 5
gadget_u[2] = 6
gadget_v[2] = 1
gadget_w[2] = 5
gadget_u[3] = 4
gadget_v[3] = 5
gadget_w[3] = 5
gadget_color = i64[4]
gadget_color[0] = 0
gadget_color[1] = 0
gadget_color[2] = 1
gadget_color[3] = 1
selected = i64[4]
planted_assignment = i32[rank]
item = 0 ## i64
while item < 4
  source_term = 0 - 1 ## i64
  term = 0 ## i64
  while term < rank && source_term < 0
    if us[term] == gadget_u[item] && vs[term] == gadget_v[item] && ws[term] == gadget_w[item]
      source_term = term
    term += 1
  ffcatt_expect("gadget source term", source_term >= 0)
  selected[item] = ffcatt_find_column(workspace, columns, source_term, gadget_color[item])
  ffcatt_expect("gadget coloured column", selected[item] >= 0)
  planted_assignment[source_term] = gadget_color[item] + 1
  item += 1
ffcatt_expect("planted cross-colour delta relation", ffpa_relation_exact(workspace.deltas(), selected, 4, workspace.words()) == 1)
g_only = i64[2]
g_only[0] = selected[0]
g_only[1] = selected[1]
ffcatt_expect("g stage alone is not exact", ffpa_relation_exact(workspace.deltas(), g_only, 2, workspace.words()) == 0)
h_only = i64[2]
h_only[0] = selected[2]
h_only[1] = selected[3]
ffcatt_expect("h stage alone is not exact", ffpa_relation_exact(workspace.deltas(), h_only, 2, workspace.words()) == 0)
stage = i64[workspace.words()]
ffcatt_expect("planted move is not binary-staged", ffcat_staging_kind(us, vs, ws, rank, n, g, workspace.images_u(), workspace.images_v(), workspace.images_w(), planted_assignment, stage) == 0)
raw_u = i64[capacity]
raw_v = i64[capacity]
raw_w = i64[capacity]
out_u = i64[capacity]
out_v = i64[capacity]
out_w = i64[capacity]
ffcat_copy_candidate(us, vs, ws, raw_u, raw_v, raw_w, rank)
term = 0
while term < rank
  choice = planted_assignment[term] ## i64
  if choice > 0
    image = (choice - 1) * rank + term ## i64
    raw_u[term] = workspace.images_u()[image]
    raw_v[term] = workspace.images_v()[image]
    raw_w[term] = workspace.images_w()[image]
  term += 1
planted_endpoint_rank = ffpan_parity_compact(raw_u, raw_v, raw_w, rank, out_u, out_v, out_w) ## i64
planted_endpoint = i64[ffw_state_size(capacity)]
endpoint_loaded = ffw_init_terms_cap(planted_endpoint, out_u, out_v, out_w, planted_endpoint_rank, n, capacity, 90105, 0, 1, 1, 1) ## i64
ffcatt_expect("planted cross-colour endpoint fully exact", planted_endpoint_rank == 8 && endpoint_loaded == planted_endpoint_rank && ffw_verify_current_exact(planted_endpoint, n) == 1 && ffpan_term_set_distance_unique(us, vs, ws, rank, out_u, out_v, out_w, planted_endpoint_rank) == 4)

best_u = i64[capacity]
best_v = i64[capacity]
best_w = i64[capacity]
meta = i64[35]
genuine = ffcat_audit_pair(us, vs, ws, rank, n, capacity, g, h, 20, 65536, 90107, workspace, best_u, best_v, best_w, meta) ## i64
ffcatt_expect("bounded coverage is explicit", meta[2] == 0 && meta[3] > meta[4] && meta[4] == 65536 && meta[32] > 0 && meta[23] == meta[1] && meta[24] == meta[1] * (meta[1] - 1) / 2 && meta[25] > 0)
ffcatt_expect("exclusive coloured relation", meta[5] > 0 && meta[10] > 0)
ffcatt_expect("every admitted relation fully gated", meta[6] == meta[7] && meta[8] == 0)
ffcatt_expect("sparse solver rediscovers cross move", genuine == meta[28] && genuine > 0 && meta[29] > 0 && meta[18] == 8 && meta[31] > 0)

<< "flipfleet_colored_automorphism_tunnel_test: all checks passed columns=" + columns.to_s() + " nullity=" + meta[1].to_s() + " combinations=" + meta[4].to_s() + " exclusive=" + meta[5].to_s() + " multicolor=" + meta[10].to_s() + " planted_cross_distance=" + ffpan_term_set_distance_unique(us, vs, ws, rank, out_u, out_v, out_w, planted_endpoint_rank).to_s() + " sampled_cross_coupled=" + genuine.to_s()
