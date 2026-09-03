# CNF encodings of corona questions.
# Run:
#   bin/tungsten spec/core/tiling_cnf_spec.w

use geometry

-> tiling_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

hex6 = Polyform.parse("H -2 2 -1 1 0 0 1 0 2 0 2 1")
search = HeeschNumber.new(hex6, 2, 20000, 5000)
tiling_check("search.depth2", search.hc == 2)

# Single-corona formula: satisfied by the corona-1 part of the witness.
corona = CoronaCnf.corona(hex6, hex6.cells)
tiling_check("corona.variables", corona.variable_count == Corona.placements(hex6, hex6.cells).size)
tiling_check("corona.kind", corona.kind == :corona)
first = []
search.witness.each ->(p)
  first.push(p) if p[0] <= 1
tiling_check("corona.witness_satisfies", corona.satisfied?(corona.assignment_of(first)))
decoded = corona.decode(corona.assignment_of(first))
tiling_check("corona.decode_verifies", CoronaWitness.verify_patch(hex6, decoded)["depth"] == 1)
# Dropping one corona tile leaves a halo cell uncovered.
partial = corona.assignment_of(first.select(->(p) p[0] == 0) + first.select(->(p) p[0] == 1)[1..-1])
tiling_check("corona.partial_fails", !corona.satisfied?(partial))

# The multilevel weak formula: every genuine corona patch satisfies it.
weak1 = CoronaCnf.weak(hex6, 1)
tiling_check("weak1.matches_corona", weak1.variable_count == corona.variable_count)
weak2 = CoronaCnf.weak(hex6, 2)
tiling_check("weak2.levels", weak2.levels.size == 2 && weak2.levels[1].size > weak2.levels[0].size)
tiling_check("weak2.witness_satisfies", weak2.satisfied?(weak2.assignment_of(search.witness)))
decoded2 = weak2.decode(weak2.assignment_of(search.witness))
verified = CoronaWitness.verify_patch(hex6, decoded2)
tiling_check("weak2.decode_verifies", verified["depth"] == 2 && !verified["outer_holes"])
tiling_check("weak2.placement_of", weak2.placement_of(weak2.levels[0].size + 1)[0] == 2)

# A hole-permitted corona satisfies the weak formula even when it has holes.
cross = Polyform.parse("O 2 0 2 1 0 2 1 2 2 2 3 2 2 3")
hsearch = HeeschNumber.new(cross, 5, 20000, 5000)
tiling_check("cross.census", hsearch.hc == 0 && hsearch.hh == 1)
weak_cross = CoronaCnf.weak(cross, 1)
tiling_check("cross.hh_witness_satisfies", weak_cross.satisfied?(weak_cross.assignment_of(hsearch.hh_witness)))

# DIMACS text.
text = weak1.dimacs
lines = text.split("\n").select(->(l) l != "")
tiling_check("dimacs.header", lines[0] == "p cnf [weak1.variable_count] [weak1.clause_count]")
tiling_check("dimacs.clause_lines", lines.size == weak1.clause_count + 1)
tiling_check("dimacs.terminated", lines[1].split(" ")[lines[1].split(" ").size - 1] == "0")

<< "tiling cnf spec: all checks passed"
