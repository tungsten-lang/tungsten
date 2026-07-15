use metaflip_worker
use flipfleet_parent_chord

-> ffpct_expect(name, condition)
  if !condition
    << "FAIL " + name
    exit(1)

n = 3 ## i64
cap = ffw_default_capacity(n) ## i64
size = ffw_state_size(cap) ## i64
base = i64[size]
base_rank = ffw_init_naive_cap(base, n, cap, 101, 0, 1, 1, 1) ## i64
ffpct_expect("naive exact", base_rank == 27 && ffw_verify_current_exact(base, n) == 1)

base_u = i64[cap]
base_v = i64[cap]
base_w = i64[cap]
z = ffw_export_current(base, base_u, base_v, base_w) ## i64
au = i64[cap]
av = i64[cap]
aw = i64[cap]
bu = i64[cap]
bv = i64[cap]
bw = i64[cap]
i = 0 ## i64
while i < base_rank
  au[i] = base_u[i]
  av[i] = base_v[i]
  aw[i] = base_w[i]
  bu[i] = base_u[i]
  bv[i] = base_v[i]
  bw[i] = base_w[i]
  i += 1

# Add two different exact line circuits on the same V/W fiber.
arank = base_rank ## i64
arank = ffpc_toggle_plain(au, av, aw, arank, cap, 1, 7, 7)
arank = ffpc_toggle_plain(au, av, aw, arank, cap, 2, 7, 7)
arank = ffpc_toggle_plain(au, av, aw, arank, cap, 3, 7, 7)
brank = base_rank ## i64
brank = ffpc_toggle_plain(bu, bv, bw, brank, cap, 1, 7, 7)
brank = ffpc_toggle_plain(bu, bv, bw, brank, cap, 4, 7, 7)
brank = ffpc_toggle_plain(bu, bv, bw, brank, cap, 5, 7, 7)
parent_a = i64[size]
parent_b = i64[size]
loaded_a = ffw_init_terms_cap(parent_a, au, av, aw, arank, n, cap, 103, 0, 1, 1, 1) ## i64
loaded_b = ffw_init_terms_cap(parent_b, bu, bv, bw, brank, n, cap, 107, 0, 1, 1, 1) ## i64
ffpct_expect("parents exact", loaded_a == 30 && loaded_b == 30 && ffw_verify_current_exact(parent_a, n) == 1 && ffw_verify_current_exact(parent_b, n) == 1)

opportunities = ffpc_count(au, av, aw, arank, bu, bv, bw, brank) ## i64
ffpct_expect("directed chords found", opportunities >= 4)
out_u = i64[cap]
out_v = i64[cap]
out_w = i64[cap]
meta = i64[8]
made = ffpc_make(au, av, aw, arank, bu, bv, bw, brank, 0, out_u, out_v, out_w, cap, meta) ## i64
ffpct_expect("one split materialized", made == 31 && meta[0] == opportunities && meta[3] == 0 && meta[7] == 1)
candidate = i64[size]
loaded = ffw_init_terms_cap(candidate, out_u, out_v, out_w, made, n, cap, 109, 0, 1, 1, 1) ## i64
ffpct_expect("materialized split globally exact", loaded == made && ffw_verify_current_exact(candidate, n) == 1)
ffpct_expect("chord approaches guide parent", meta[6] < arank + brank - 2 * (base_rank + 1))

wrapped = i64[size]
wrapped_rank = ffpc_state_into(wrapped, parent_a, parent_b, opportunities + 1, 113) ## i64
ffpct_expect("state wrapper exact", wrapped_rank == 31 && ffw_verify_current_exact(wrapped, n) == 1)
ffpct_expect("identical parents miss", ffpc_state_into(wrapped, parent_a, parent_a, 0, 127) == 0)

<< "parent chord tests passed opportunities=" + opportunities.to_s() + " rank=" + arank.to_s() + "->" + made.to_s() + " distance=" + meta[6].to_s()
