# Corona formulas solved by wassat and refutations checked by wrat: the
# end-to-end route a Heesch-number certificate takes.
# Run:
#   bin/tungsten spec/core/tiling_wassat_spec.w

use geometry
use wassat
use wrat

-> tiling_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

# A corona of the 6-hex found by the SAT solver decodes to a verified patch.
hex6 = Polyform.parse("H -2 2 -1 1 0 0 1 0 2 0 2 1")
corona = CoronaCnf.corona(hex6, hex6.cells)
result = wassat_solve_mode_limited(corona.dimacs, WASSAT_PROOF_NONE, 0, 0)
tiling_check("wassat.corona_sat", result["sat"])
patch = CoronaWitness.verify_patch(hex6, corona.decode(result["model"]))
tiling_check("wassat.corona_decodes", patch["depth"] == 1)

# The heptomino with Hc = 0, Hh = 1: a hole-permitted first corona exists,
# a second does not, and the weak formula's UNSAT certificate is checked by
# an independent checker — Hh <= 1, so the shape is not a plane tiler.
cross = Polyform.parse("O 2 0 2 1 0 2 1 2 2 2 3 2 2 3")
weak1 = CoronaCnf.weak(cross, 1)
sat1 = wassat_solve_mode_limited(weak1.dimacs, WASSAT_PROOF_NONE, 0, 0)
tiling_check("wassat.weak1_sat", sat1["sat"])
patch1 = CoronaWitness.verify_patch(cross, weak1.decode(sat1["model"]))
tiling_check("wassat.weak1_decodes", patch1["depth"] == 1 && patch1["outer_holes"])

weak2 = CoronaCnf.weak(cross, 2)
text2 = weak2.dimacs
unsat = wassat_solve_mode_limited(text2, WASSAT_PROOF_DRAT, 0, 0)
tiling_check("wassat.weak2_unsat", unsat["unsat"])
proof = unsat["drat"].join("\n") + "\n"
check = wrat_verify(text2, proof)
tiling_check("wrat.certificate_verified", check["verified"] == true)

<< "tiling wassat spec: all checks passed"
