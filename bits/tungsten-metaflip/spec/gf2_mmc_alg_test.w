# The composition primitives of matmulcatalog over GF(2) (lib/metaflip/gf2/mmc_alg.w) against the Python original
# (tools/mmc_gf2_alg.py): orientations, axis permutations, Kronecker products, concatenation (also in another orientation),
# projection, recombination, bud decompositions and the serendipitous product, on 19 input schemes (naive, Strassen,
# products of them, the 3x3x4 seed of rank 29, a scheme with zero and repeated terms). The goldens in
# spec/fixtures/gf2_mmc_alg are what the original returns, term order included (generate.py runs it). Prints FAIL lines
# and exits 1 on a mismatch.
use core/system
use ../lib/metaflip/gf2/mmc_alg
use ../lib/metaflip/gf2/jsonx
use ../lib/metaflip/gf2/textx

failures = 0 ## i64
checks = 0 ## i64

fixtures = __DIR__ + "/fixtures/gf2_mmc_alg"

-> expect(label, got, want)
  if got != want
    << "FAIL " + label + ": got " + got.to_s.slice(0, 300) + " want " + want.to_s.slice(0, 300)
    return 1
  0

# the schemes: name => Scheme
schemes = {}
Textx.splitlines(read_file(fixtures + "/schemes.tsv")).each -> (line)
  fields = line.split("\t")
  dims = fields[1].split(" ").map(-> (d) d.to_i)
  terms = fields[2].split(" ; ").map -> (text)
    words = text.split(" ")
    [Metaflip:Gf2:Bits.from_hex(words[0]), Metaflip:Gf2:Bits.from_hex(words[1]), Metaflip:Gf2:Bits.from_hex(words[2])]
  schemes[fields[0]] = Metaflip:Gf2:Scheme.from_terms(dims[0], dims[1], dims[2], terms)

# `NxMxP rR sha256` of the terms in order
-> digest(a)
  text = StringBuffer()
  a.terms.each -> (term)
    text << Metaflip:Gf2:Bits.to_hex(term[0]) + " " + Metaflip:Gf2:Bits.to_hex(term[1]) + " " + Metaflip:Gf2:Bits.to_hex(term[2]) + "\n"
  a.n.to_s + "x" + a.m.to_s + "x" + a.p.to_s + " r" + a.rank.to_s + " " + Digest.sha256(text.to_s)

-> scheme_result(a)
  a == nil ? ["none"] : [digest(a)]

# the lookups and ranks of the original's tests
strassen = schemes["strassen"]
lookup_strassen = -> (size)
  naive = Metaflip:Gf2:Scheme.naive(size[0], size[1], size[2])
  size[0] == 2 && size[1] == 2 && size[2] == 2 ? strassen : naive
rank_strassen = -> (size)
  size[0] == 2 && size[1] == 2 && size[2] == 2 ? 7 : size[0] * size[1] * size[2]
big = -> (size)
  size[0] > 4 || size[1] > 4 || size[2] > 4
lookup_none_big = -> (size)
  big.call(size) ? nil : Metaflip:Gf2:Scheme.naive(size[0], size[1], size[2])
rank_none_big = -> (size)
  big.call(size) ? nil : size[0] * size[1] * size[2]

-> run(spec, schemes, strassen, lookups)
  op = spec["op"]
  a = spec.key?("a") ? schemes[spec["a"]] : nil
  b = spec.key?("b") ? schemes[spec["b"]] : nil
  return scheme_result(Metaflip:Gf2:MmcAlg.apply_orientation(a, spec["code"])) if op == "orient"
  return scheme_result(Metaflip:Gf2:MmcAlg.orient_by_perm(a, spec["perm"])) if op == "orient_by_perm"
  return scheme_result(a.orient_as(spec["shape"])) if op == "orient_as"
  return scheme_result(Metaflip:Gf2:MmcAlg.permute_axes(a, spec["perm"])) if op == "permute_axes"
  if op == "s3_orbit"
    out = []
    Metaflip:Gf2:MmcAlg.s3_orbit_with_perms(a).each -> (pair)
      out.push(pair[1])
      out.push(digest(pair[0]))
    return out
  return Metaflip:Gf2:MmcAlg.orientations(a).map(-> (o) digest(o)) if op == "orientations"
  return scheme_result(Metaflip:Gf2:MmcAlg.axis_permute(a, spec["pA"], spec["pB"], spec["pC"])) if op == "axis_permute"
  return scheme_result(Metaflip:Gf2:MmcAlg.kron(a, b)) if op == "kron"
  return scheme_result(Metaflip:Gf2:MmcAlg.concat_cols(a, b)) if op == "concat_cols"
  return scheme_result(Metaflip:Gf2:MmcAlg.concat_rows(a, b)) if op == "concat_rows"
  return scheme_result(Metaflip:Gf2:MmcAlg.concat_inner_r(a, b)) if op == "concat_inner"
  return scheme_result(Metaflip:Gf2:MmcAlg.concat_right(a, b)) if op == "concat_right"
  return scheme_result(Metaflip:Gf2:MmcAlg.project(a, spec["keepN"], spec["keepM"], spec["keepP"])) if op == "project"
  if op == "recombination"
    lookup = spec["lookup"] == "strassen" ? lookups[0] : lookups[2]
    return scheme_result(Metaflip:Gf2:MmcAlg.recombination(a, spec["allocA"], spec["allocB"], spec["allocC"], lookup))
  if op == "buds"
    found = Metaflip:Gf2:MmcAlg.find_buds(a, spec["order"])
    out = found[0].map(-> (bud) bud[0] + ":" + bud[1].map(-> (l) l.to_s).join(","))
    out.push("trivial:" + found[1].map(-> (l) l.to_s).join(","))
    return out
  if op == "serendipitous"
    resolve = spec["res"] == "strassen" ? lookups[0] : lookups[2]
    rank_of = spec["res"] == "strassen" ? lookups[1] : lookups[3]
    return scheme_result(Metaflip:Gf2:MmcAlg.serendipitous(a, spec["n2"], spec["m2"], spec["p2"], resolve, rank_of))
  return scheme_result(Metaflip:Gf2:MmcAlg.clean(a)) if op == "clean"
  raise "unknown operation " + op

lookups = [lookup_strassen, rank_strassen, lookup_none_big, rank_none_big]
Jsonx.load(fixtures + "/cases.json").each_with_index -> (spec, index)
  got = nil
  begin
    got = run(spec, schemes, strassen, lookups)
  rescue e: MmcError
    got = {"error" => e.message}
  checks += 1
  failures += expect(spec["op"] + " #" + index.to_s + " " + (spec.key?("a") ? spec["a"] : ""), got, spec["out"])

if failures > 0
  << "FAIL " + failures.to_s + " of " + checks.to_s + " mmc algebra checks"
  exit(1)
<< "PASS gf2 mmc algebra: " + checks.to_s + " checks"
