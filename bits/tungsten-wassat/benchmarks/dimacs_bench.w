# Head-to-head: the runtime's scalar C DIMACS scanner vs a Lex16 scanner.
#
#   tungsten compile bits/tungsten-wassat/benchmarks/dimacs_bench.w --out db
#   ./db <file.cnf> [rounds]
#
# Both fill the SAME slab (lits/offs/lens as i64[], a clause being the slice
# (offs[k], lens[k]) of lits) and the outputs are compared cell by cell -- a
# speed number from a scanner that parses differently is worthless.

use ./dimacs_lex16

src = read_file(argv()[0])
rounds = argv().size > 1 ? argv()[1].to_i : 5
cap = src.size / 2 + 64

litsA = i64[cap]
offsA = i64[cap]
lensA = i64[cap]
hdrA = i64[8]
litsB = i64[cap]
offsB = i64[cap]
lensB = i64[cap]
hdrB = i64[8]

z = ccall("__w_parse_dimacs", src, litsA, offsA, lensA, hdrA)
t0 = ccall("__w_clock_ms")
i = 0
while i < rounds
  z = ccall("__w_parse_dimacs", src, litsA, offsA, lensA, hdrA)
  i += 1
ms_c = ccall("__w_clock_ms") - t0

tl = ccall("__w_clock_ms")
lc = src.lchs("tungsten", bits: 16)
pack_ms = ccall("__w_clock_ms") - tl
n = lc.size

z = wassat_dimacs_lex16(lc, n, litsB, offsB, lensB, hdrB, cap, cap)
t1 = ccall("__w_clock_ms")
i = 0
while i < rounds
  z = wassat_dimacs_lex16(lc, n, litsB, offsB, lensB, hdrB, cap, cap)
  i += 1
ms_l = ccall("__w_clock_ms") - t1

<< "bytes=[src.size] lexchars=[n] rounds=[rounds]"
<< "  C scalar      : [ms_c / rounds] ms/parse"
<< "  Lex16 scan    : [ms_l / rounds] ms/parse   (+ [pack_ms] ms one-off pack)"
<< "  Lex16 TOTAL   : [ms_l / rounds + pack_ms] ms/parse"

bad = 0
if hdrA[0] != hdrB[0]
  << "MISMATCH nvars [hdrA[0]] vs [hdrB[0]]"
  bad += 1
if hdrA[2] != hdrB[2]
  << "MISMATCH clauses [hdrA[2]] vs [hdrB[2]]"
  bad += 1
if hdrA[3] != hdrB[3]
  << "MISMATCH literals [hdrA[3]] vs [hdrB[3]]"
  bad += 1
if bad == 0
  k = 0
  while k < hdrA[3] && bad < 3
    if litsA[k] != litsB[k]
      << "MISMATCH lit [k]: [litsA[k]] vs [litsB[k]]"
      bad += 1
    k += 1
if bad == 0
  << "OUTPUTS IDENTICAL"
else
  << "OUTPUTS DIFFER"
