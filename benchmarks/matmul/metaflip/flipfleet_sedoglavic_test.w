use flipfleet_sedoglavic

root = "benchmarks/matmul/metaflip/"
p444 = root + "matmul_4x4_rank47_d450_gf2.txt"
p334 = root + "matmul_3x3x4_rank29_gf2.txt"
p344 = root + "matmul_3x4x4_rank38_gf2.txt"

out0 = "/tmp/flipfleet_sedoglavic_d2952.txt"
out1 = "/tmp/flipfleet_sedoglavic_d2958.txt"
out2 = "/tmp/flipfleet_sedoglavic_d3015.txt"
r0 = ffsc_compose_files(p444, p334, p344, out0, 0) ## i64
r1 = ffsc_compose_files(p444, p334, p344, out1, 1) ## i64
r2 = ffsc_compose_files(p444, p334, p344, out2, 2) ## i64
if r0 != 248 || r1 != 248 || r2 != 248
  << "FAIL rank " + r0.to_s() + " " + r1.to_s() + " " + r2.to_s()
  exit(1)

us = i64[384]
vs = i64[384]
ws = i64[384]
q0 = ffsc_load(out0, us, vs, ws, 384) ## i64
if q0 != 248 || ffsc_verify_exact(us, vs, ws, q0, 7, 7, 7) != 1
  << "FAIL d2952 reload/exact"
  exit(1)
if ffsc_density(us, vs, ws, q0) != 2952
  << "FAIL d2952 density " + ffsc_density(us, vs, ws, q0).to_s()
  exit(1)

q1 = ffsc_load(out1, us, vs, ws, 384) ## i64
if q1 != 248 || ffsc_verify_exact(us, vs, ws, q1, 7, 7, 7) != 1
  << "FAIL d2958 reload/exact"
  exit(1)
if ffsc_density(us, vs, ws, q1) != 2958
  << "FAIL d2958 density " + ffsc_density(us, vs, ws, q1).to_s()
  exit(1)

q2 = ffsc_load(out2, us, vs, ws, 384) ## i64
if q2 != 248 || ffsc_verify_exact(us, vs, ws, q2, 7, 7, 7) != 1
  << "FAIL d3015 reload/exact"
  exit(1)
if ffsc_density(us, vs, ws, q2) != 3015
  << "FAIL d3015 density " + ffsc_density(us, vs, ws, q2).to_s()
  exit(1)

if read_file(out0) != read_file(root + "matmul_7x7_rank248_d2952_sedoglavic_gf2.txt")
  << "FAIL checked-in d2952 is not reproducible"
  exit(1)
if read_file(out1) != read_file(root + "matmul_7x7_rank248_d2958_sedoglavic_gf2.txt")
  << "FAIL checked-in d2958 is not reproducible"
  exit(1)
if read_file(out2) != read_file(root + "matmul_7x7_rank248_d3015_connectivity_sedoglavic_gf2.txt")
  << "FAIL checked-in d3015 is not reproducible"
  exit(1)

<< "flipfleet_sedoglavic_test: all checks passed"
