# The construction functions of lib/metaflip/gf2/derive.w against the Python originals: block embedding, Kronecker
# products, coordinate projection, the matrix factorisation, shared-factor compression and the basis rewrite. The goldens
# in spec/fixtures/gf2_derive/expected/cases.tsv are SHA-256 digests of each original's result, terms in the order it
# returns them (spec/fixtures/gf2_derive/generate.py runs the originals). Prints FAIL lines and exits 1 on a mismatch.
use core/system
use ../lib/metaflip/gf2/derive
use ../lib/metaflip/gf2/record_board

failures = 0 ## i64
checks = 0 ## i64

fixtures = __DIR__ + "/fixtures/gf2_derive"

-> read_lines(path)
  text = read_file(path)
  raise "missing " + path if text == nil
  text.split("\n").select(-> (line) line != "")

-> terms_of(name)
  Metaflip:Gf2:RecordBoard.decimal_terms(read_file(fixtures + "/in/" + name + ".txt"))

-> shape_of(name)
  row = read_lines(fixtures + "/in/shapes.tsv").select(-> (line) line.split("\t")[0] == name)[0].split("\t")
  row[1].split("x").map(-> (d) d.to_i)

# The text the generator digests: one `u v w` hexadecimal line per term, then `extra`.
-> lines_of(terms, extra)
  terms.map(-> (t) Metaflip:Gf2:Bits.to_hex(t[0]) + " " + Metaflip:Gf2:Bits.to_hex(t[1]) + " " + Metaflip:Gf2:Bits.to_hex(t[2]) + "\n").join("") + extra

-> shape_text(shape)
  shape.map(-> (d) d.to_s).join("x")

# name => [rank, digest] of the golden file.
golden = {}
read_lines(fixtures + "/expected/cases.tsv").each -> (line)
  fields = line.split("\t")
  golden[fields[0]] = [fields[1].to_i, fields[2]]

-> expect_case(golden, name, terms, extra) i64
  want = golden[name]
  raise "no golden for " + name if want == nil
  got = Digest.sha256(lines_of(terms, extra))
  if terms.size != want[0] || got != want[1]
    << "FAIL " + name + ": rank " + terms.size.to_s + " (want " + want[0].to_s + "), digest " + got.slice(0, 12) + " (want " + want[1].slice(0, 12) + ")"
    return 1
  0

-> history_text(history)
  history.map(-> (h) h["axis"].to_s + " " + Metaflip:Gf2:Bits.to_hex(h["fixed"]) + " " + h["before"].to_s + " " + h["after"].to_s + "\n").join("")

-> changed_text(changed)
  changed.map(-> (c) Metaflip:Gf2:Bits.to_hex(c["fixed"]) + " " + c["before"].to_s + " " + c["after"].to_s + "\n").join("")

# block
["strassen", "s234", "s256"].each -> (name)
  shape = shape_of(name)
  terms = terms_of(name)
  [[[shape[0] + 1, shape[1] + 2, shape[2] + 3], [0, 0, 0]], [[shape[0] + 2, shape[1] + 1, shape[2] + 1], [1, 0, 1]], [[shape[0] * 2, shape[1], shape[2] * 2], [shape[0], 0, shape[2]]]].each -> (spec)
    checks += 1
    failures += expect_case(golden, "block:" + name + ":" + shape_text(spec[0]) + ":" + spec[1].join(""), Metaflip:Gf2:Derive.block(shape, terms, spec[0], spec[1]), "")

# Kronecker products
[["strassen", "strassen"], ["strassen", "s234"], ["s225", "strassen"], ["s234", "s225"]].each -> (pair)
  checks += 1
  failures += expect_case(golden, "kron:" + pair[0] + ":" + pair[1], Metaflip:Gf2:Derive.kronecker(shape_of(pair[0]), terms_of(pair[0]), shape_of(pair[1]), terms_of(pair[1])), "")

# coordinate projection
["strassen", "s234", "s225", "s235p2"].each -> (name)
  shape = shape_of(name)
  terms = terms_of(name)
  3.times -> (dimension)
    shape[dimension].times -> (coordinate)
      projected = Metaflip:Gf2:Derive.project(shape, terms, dimension, coordinate)
      checks += 1
      failures += expect_case(golden, "project:" + name + ":" + dimension.to_s + ":" + coordinate.to_s, projected[1], shape_text(projected[0]) + "\n")

# matrix factorisations of random pair lists
12.times -> (trial)
  pairs = read_lines(fixtures + "/in/pairs_" + trial.to_s + ".txt").map(-> (line) [line.split(" ")[0].to_i, line.split(" ")[1].to_i])
  [false, true].each -> (reverse)
    factors = Metaflip:Gf2:Derive.matrix_factors(pairs, 128, reverse)
    checks += 1
    failures += expect_case(golden, "factors:" + trial.to_s + ":" + (reverse ? "1" : "0"), factors.map(-> (f) [f[0], f[1], 1]), "")

# shared-factor compression and the basis rewrite
["strassen", "s234", "s225", "s235p2", "s256", "strassen_split", "s234_split", "s256_split"].each -> (name)
  terms = terms_of(name)
  compressed = Metaflip:Gf2:Derive.compress_shared(terms, 256)
  checks += 1
  failures += expect_case(golden, "compress:" + name, compressed[0], history_text(compressed[1]))
  3.times -> (axis)
    [false, true].each -> (reverse)
      rewritten = Metaflip:Gf2:Derive.refactor_shared(terms, axis, 256, reverse)
      checks += 1
      failures += expect_case(golden, "refactor:" + name + ":" + axis.to_s + ":" + (reverse ? "1" : "0"), rewritten[0], changed_text(rewritten[1]))

# the two-pass basis rewrite and the projection children of the screens
["strassen", "s234", "s225", "s235p2", "s256", "s234_split"].each -> (name)
  shape = shape_of(name)
  terms = terms_of(name)
  (6..17).each -> (mode)
    checks += 1
    failures += expect_case(golden, "basis:" + name + ":" + mode.to_s, Metaflip:Gf2:Derive.two_pass(terms, shape, mode), "")
["s234", "s235p2", "s234_split"].each -> (name)
  shape = shape_of(name)
  terms = terms_of(name)
  3.times -> (axis)
    [0, shape[axis] - 1].each -> (coordinate)
      child = Metaflip:Gf2:Derive.child(shape, terms, axis, coordinate)
      checks += 1
      failures += expect_case(golden, "child:" + name + ":" + axis.to_s + ":" + coordinate.to_s, child[1], shape_text(child[0]) + "\n" + history_text(child[2]))

if failures > 0
  << "FAIL " + failures.to_s + " of " + checks.to_s + " derive checks"
  exit(1)
<< "PASS gf2 derive: " + checks.to_s + " checks"
