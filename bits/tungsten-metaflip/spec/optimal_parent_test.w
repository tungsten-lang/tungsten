use ../lib/metaflip/fleet/optimal_parent

root = "/tmp/metaflip-optimal-orbit-" + ccall("__w_clock_ms").to_s()
capacity = ffw_default_capacity(2) ## i64
base = i64[ffw_state_size(capacity)]
candidate = i64[ffw_state_size(capacity)]
us = i64[7]
vs = i64[7]
ws = i64[7]
path = __DIR__ + "/../lib/metaflip/seeds/gf2/matmul_2x2_rank7_strassen_gf2.txt"
if ffw_load_scheme_cap(base,path,2,capacity,17,0,1,1,1) != 7
  exit(1)
refinement = MetaflipRefinement.new(root,System.executable_path())
pass = 0 ## i64
while pass < 2
  code = 0 ## i64
  while code < 216
    if ffop_candidate(base,code,candidate,us,vs,ws,capacity) != 1 || refinement.submit(candidate,2,2,2) < 0
      exit(1)
    code += 1
  if refinement.submitted != 36 || refinement.failures != 0
    << "FAIL orbit cardinality " + refinement.submitted.to_s()
    exit(1)
  pass += 1
if ffop_candidate(base,216,candidate,us,vs,ws,capacity) != 0 || ffop_candidate(base,0-1,candidate,us,vs,ws,capacity) != 0
  exit(1)
z = refinement.stop()
<< "PASS 216 exact orbit codes, 36 literal parents, repeated visit adds no tickets"
<< "ORBIT_ROOT " + root
