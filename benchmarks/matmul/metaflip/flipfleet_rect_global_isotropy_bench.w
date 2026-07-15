use flipfleet_rect_global_isotropy

arguments = argv()
restarts = 256 ## i64
output = "/tmp/matmul_2x3x4_rank20_global_isotropy_gf2.txt"
if arguments.size() > 0
  restarts = arguments[0].to_i()
if arguments.size() > 1
  output = arguments[1]
if restarts < 0
  restarts = 0
if restarts > 4096
  restarts = 4096

path = "benchmarks/matmul/metaflip/matmul_2x3x4_rank20_catalog_gf2.txt"
source = ffbc_load_exact(path, 2, 3, 4, 64)
if source == nil || source.rank() != 20
  << "RECT_GLOBAL_ISOTROPY_LOAD_FAIL"
  exit(1)
stats = i64[4]
best = ffrgir_multistart(source, restarts, 64, stats)
if best == nil || best.rank() != 20 || ffbc_verify_exact(best) != 1
  << "RECT_GLOBAL_ISOTROPY_GATE_FAIL"
  exit(1)
if ffbc_write(output, best) != 20
  << "RECT_GLOBAL_ISOTROPY_WRITE_FAIL"
  exit(1)
reparsed = ffbc_load_exact(output, 2, 3, 4, 64)
if reparsed == nil || fflc_density(reparsed) != fflc_density(best)
  << "RECT_GLOBAL_ISOTROPY_REPARSE_FAIL"
  exit(1)
<< "RECT_GLOBAL_ISOTROPY_SUMMARY shape=2x3x4 rank=20 source-density=" + stats[0].to_s() + " best-density=" + stats[1].to_s() + " descent-steps=" + stats[2].to_s() + " restarts=" + stats[3].to_s() + " distance=" + fflc_term_set_distance(source, best).to_s() + " exact=1 reparsed=1 output=" + output
