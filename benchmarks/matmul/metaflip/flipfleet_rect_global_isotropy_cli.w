# Generate an exact whole-scheme GL image for a rectangular GF(2) seed.
#
# This is deliberately an offline seed tool: it never touches the native
# campaign coordinator or its TUI.  The multistart descent searches sparse
# row/inner/column basis changes and complete-gates every intermediate image.
#
# Usage:
#   flipfleet_rect_global_isotropy_cli SEED N M P RESTARTS MAX_STEPS OUTPUT

use flipfleet_rect_global_isotropy

arguments = argv()
if arguments.size() != 7
  << "usage: flipfleet_rect_global_isotropy_cli SEED N M P RESTARTS MAX_STEPS OUTPUT"
  exit(2)

seed_path = arguments[0]
n = arguments[1].to_i() ## i64
m = arguments[2].to_i() ## i64
p = arguments[3].to_i() ## i64
restarts = arguments[4].to_i() ## i64
max_steps = arguments[5].to_i() ## i64
output_path = arguments[6]

if n < 1 || m < 1 || p < 1 || n*m > 63 || m*p > 63 || n*p > 63
  << "RECT_GLOBAL_ISOTROPY_CLI_ERROR code=shape"
  exit(2)
if restarts < 0 || restarts > 4096 || max_steps < 1 || max_steps > 256
  << "RECT_GLOBAL_ISOTROPY_CLI_ERROR code=bounds"
  exit(2)

source = ffbc_load_exact(seed_path,n,m,p,512)
if source == nil || source.rank() < 1 || ffbc_verify_exact(source) != 1
  << "RECT_GLOBAL_ISOTROPY_CLI_ERROR code=seed path=" + seed_path
  exit(1)

stats = i64[4]
best = ffrgir_multistart(source,restarts,max_steps,stats)
if best == nil || best.rank() != source.rank() || ffbc_verify_exact(best) != 1
  << "RECT_GLOBAL_ISOTROPY_CLI_ERROR code=gate"
  exit(1)
if ffbc_write(output_path,best) != best.rank()
  << "RECT_GLOBAL_ISOTROPY_CLI_ERROR code=write path=" + output_path
  exit(1)

reparsed = ffbc_load_exact(output_path,n,m,p,512)
if reparsed == nil || reparsed.rank() != best.rank() || ffbc_verify_exact(reparsed) != 1 || fflc_density(reparsed) != fflc_density(best)
  << "RECT_GLOBAL_ISOTROPY_CLI_ERROR code=reparse path=" + output_path
  exit(1)

<< "RECT_GLOBAL_ISOTROPY_CLI shape=" + n.to_s() + "x" + m.to_s() + "x" + p.to_s() + " rank=" + best.rank().to_s() + " source_density=" + stats[0].to_s() + " best_density=" + stats[1].to_s() + " descent_steps=" + stats[2].to_s() + " restarts=" + stats[3].to_s() + " distance=" + fflc_term_set_distance(source,best).to_s() + " exact=1 reparsed=1 output=" + output_path
