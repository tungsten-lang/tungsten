# Coronas, Heesch numbers and witness verification.
# Run:
#   bin/tungsten spec/core/tiling_corona_spec.w
#
# Reference values are Kaplan's exhaustive census (Heesch numbers of
# unmarked polyforms, 2022): the four non-tiling 6-hexes, the three
# non-tiling 7-ominoes and the non-tiling 7-iamond.

use geometry

-> tiling_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

# ---- witness verification --------------------------------------------------

witness = "H 0 0 0 1 1 1 2 1 3 1 4 0\n~ 1 1 1\n9\n0 <1,0,0,0,1,0>\n1 <0,-1,2,1,1,-4>\n1 <-1,-1,7,1,0,-4>\n1 <-1,-1,2,1,0,2>\n1 <-1,-1,0,1,0,2>\n1 <1,0,-5,0,1,1>\n1 <1,1,1,-1,0,3>\n1 <-1,0,8,0,-1,-1>\n1 <0,1,-1,-1,-1,0>\n"
v = CoronaWitness.verify_text(witness)
tiling_check("witness.accepted", v["hc"] == 1 && v["hh"] == 1 && v["claim_met"])
tiling_check("witness.levels", v["patch"]["levels"] == [0, 1, 1, 1, 1, 1, 1, 1, 1])
tiling_check("witness.patch_cells", v["patch"]["patch_cells"].size == 54)

-> rejection_code(text)
  begin
    CoronaWitness.verify_text(text)
  rescue e
    return "[e]".split(":")[0]
  "ACCEPTED"

tiling_check("witness.level_mismatch",
             rejection_code(witness.gsub("1 <0,-1,2,1,1,-4>", "2 <0,-1,2,1,1,-4>")) == "PATCH_LEVEL_MISMATCH")
tiling_check("witness.gap",
             rejection_code(witness.gsub("9\n", "8\n").gsub("1 <0,1,-1,-1,-1,0>\n", "")) == "PATCH_GAP")
tiling_check("witness.overlap",
             rejection_code(witness.gsub("1 <0,-1,2,1,1,-4>", "1 <1,0,0,0,1,0>")) == "PATCH_OVERLAP")
tiling_check("witness.shear",
             rejection_code(witness.gsub("1 <0,-1,2,1,1,-4>", "1 <1,1,2,0,1,-4>")) == "XFORM_NOT_SYMMETRY")
tiling_check("witness.no_central",
             rejection_code(witness.gsub("0 <1,0,0,0,1,0>", "1 <1,0,0,0,1,0>")) == "PATCH_NO_CENTRAL_TILE")

# ---- placements -----------------------------------------------------------

eleven = Polyform.parse("H -3 2 -3 4 -2 2 -2 4 -1 1 -1 3 0 0 0 1 0 2 0 3 1 0")
tiling_check("placements.eleven_hex", Corona.placements(eleven, eleven.cells).size == 380)
covers = Corona.covers(eleven, eleven.cells, 3)
tiling_check("covers.exist", covers.size == 3)
tiling_check("covers.cover_halo",
             Corona.union(eleven.cells, covers[0]).size == eleven.size + covers[0].size * eleven.size)

# ---- Heesch numbers ---------------------------------------------------------

-> heesch_of(text, max_level, nodes)
  HeeschNumber.new(Polyform.parse(text), max_level, 20000, nodes)

h = heesch_of("H -1 1 0 0 1 0 2 0 3 0 3 1", 5, 5000)
tiling_check("census.hex6_b", h.hc == 1 && h.hh == 1 && h.exhaustive?)
h = heesch_of("H -2 2 -1 1 0 0 1 0 1 1 1 2", 5, 5000)
tiling_check("census.hex6_c", h.hc == 1 && h.hh == 1 && h.exhaustive?)
h = heesch_of("H -3 1 -2 1 -2 2 -2 3 -1 1 0 0", 5, 5000)
tiling_check("census.hex6_d", h.hc == 1 && h.hh == 1 && h.exhaustive?)
h = heesch_of("O 1 0 1 1 0 2 1 2 1 3 2 3 3 3", 5, 5000)
tiling_check("census.omino7_a", h.hc == 1 && h.hh == 1 && h.exhaustive?)
h = heesch_of("O 0 0 4 0 0 1 1 1 2 1 3 1 4 1", 5, 5000)
tiling_check("census.omino7_b", h.hc == 1 && h.hh == 1 && h.exhaustive?)
h = heesch_of("I -8 1 -6 0 -3 -3 -2 -5 -5 1 -3 0 -2 -2", 5, 5000)
tiling_check("census.iamond7", h.hc == 1 && h.hh == 1 && h.exhaustive?)

# Hc = 0 but Hh = 1: it can be surrounded only with holes.
h = heesch_of("O 2 0 2 1 0 2 1 2 2 2 3 2 2 3", 5, 5000)
tiling_check("census.omino7_c", h.hc == 0 && h.hh == 1 && h.exhaustive?)
hh_patch = CoronaWitness.verify_patch(h.shape, h.hh_witness)
tiling_check("census.omino7_c.hh_witness", hh_patch["depth"] == 1 && hh_patch["outer_holes"])
parsed = CoronaWitness.verify_text(h.witness_text)
tiling_check("census.omino7_c.text", parsed["hc"] == 0 && parsed["hh"] == 1)

# Hc = 2: stopping at the requested depth gives a fast verified witness.
h = heesch_of("H -2 2 -1 1 0 0 1 0 2 0 2 1", 2, 5000)
tiling_check("census.hex6_a.lower_bound", h.hc == 2 && !h.exhaustive?)
w = CoronaWitness.verify_text(h.witness_text)
tiling_check("census.hex6_a.witness", w["hc"] == 2 && w["hh"] == 2 && w["claim_met"])

<< "tiling corona spec: all checks passed"
