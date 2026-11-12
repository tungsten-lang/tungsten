# The lineage bundle builder (lib/metaflip/gf2/lineage.w, Lineage.build) against the Python original's test
# (spec/build_gf2_lineage_bundle_test.py): chains of a closure seed, a basis rewrite and a projection are written as
# compressed certificates and a manifest, the shared root is stored once, parents are linked, the verifier accepts the
# bundle, and a tensor reached with different provenance, an unseeded chain and a seed kind in mid-chain are refused.
# Prints FAIL lines and exits 1 on a mismatch.
use core/system
use ../lib/metaflip/gf2/lineage
use ../lib/metaflip/gf2/derive
use ../lib/metaflip/gf2/record_board
use ../lib/metaflip/gf2/jsonx
use ../lib/metaflip/gf2/fsx

failures = 0 ## i64
checks = 0 ## i64

-> expect(label, got, want)
  if got != want
    << "FAIL " + label + ": got " + got.to_s.slice(0, 200) + " want " + want.to_s.slice(0, 200)
    return 1
  0

-> refused?(spec, out)
  refused = false
  begin
    Metaflip:Gf2:Lineage.build(spec, out)
  rescue e: LineageError
    refused = true
  refused

name = "matmul_3x3x4_rank29_d249_peterson_2026_aws_disjoint_gf2.txt"
seed = __DIR__ + "/fixtures/gf2_lineage/in/repo/lib/metaflip/seeds/gf2/" + name
text = read_file(seed)
scheme = Metaflip:Gf2:RecordBoard.decode_scheme(seed, text)
shape = scheme.shape
base = scheme.terms.sort
base_blob = Metaflip:Gf2:Lineage.blob(shape, base)

Fsx.with_tempdir(prefix: "gf2-lineage-build-") -> (tmp)
  mode = 6
  mode += 1 while Metaflip:Gf2:Lineage.blob(shape, Metaflip:Gf2:Derive.two_pass(base, shape, mode)) == base_blob && mode < 12
  Fsx.write(tmp + "/basis.mfw", Metaflip:Gf2:Lineage.blob(shape, Metaflip:Gf2:Derive.two_pass(base, shape, mode)))
  child = Metaflip:Gf2:Derive.child(shape, base, 2, 0)
  Fsx.write(tmp + "/child.mfw", Metaflip:Gf2:Lineage.blob(child[0], child[1]))
  recipe = {"kind" => "seed", "rank" => 29, "shape" => [3, 3, 4], "source" => "metaflip/seeds/gf2/" + name, "source_sha256" => Digest.sha256(text)}
  root = {"kind" => "closure", "file" => seed, "details" => {"recipe" => recipe}}
  basis_step = {"kind" => "basis", "file" => tmp + "/basis.mfw", "details" => {"mode" => mode}}
  child_step = {"kind" => "projection", "file" => tmp + "/child.mfw", "details" => {"mode" => nil, "axis" => 2, "coordinate" => 0}}
  spec = {"walker" => "bits/tungsten-metaflip/tools/wide_rect_walk.w", "chains" => [[root, basis_step], [root, child_step]]}
  manifest = Metaflip:Gf2:Lineage.build(spec, tmp + "/bundle")
  rows = manifest["rows"]
  checks += 1
  failures += expect("a shared root is stored once", rows.map(-> (row) row["kind"]), ["closure", "basis", "projection"])
  checks += 1
  failures += expect("the children name the root as their parent", [rows[1]["parent"], rows[2]["parent"], rows[0]["parent"]], [rows[0]["sha256"], rows[0]["sha256"], nil])
  checks += 1
  failures += expect("the row files are named after shape, rank and digest", rows[0]["file"], "3x3x4-r29-" + rows[0]["sha256"].slice(0, 8) + ".mfw.gz.b64")
  checks += 1
  failures += expect("the manifest on disk is the manifest returned", Jsonx.load(tmp + "/bundle/manifest.json"), manifest)
  checks += 1
  failures += expect("the walker is recorded", manifest["walker"], "bits/tungsten-metaflip/tools/wide_rect_walk.w")
  verified = Metaflip:Gf2:Lineage.verify(tmp + "/bundle", {})
  checks += 1
  failures += expect("the verifier accepts the bundle", verified["summary"], "PASS 3 exact GF(2) tensors (Tungsten, two gates); rows: 1 basis, 1 closure, 1 projection")
  checks += 1
  exists = false
  begin
    Metaflip:Gf2:Lineage.build(spec, tmp + "/bundle")
  rescue e: FsError
    exists = true
  failures += expect("an existing output directory is refused", exists, true)

  again = {"chains" => [[root, basis_step, {"kind" => "basis", "file" => seed, "details" => {"mode" => mode}}]]}
  checks += 1
  failures += expect("the same tensor with different provenance", refused?(again, tmp + "/bad-cycle"), true)
  unseeded = {"chains" => [[{"kind" => "basis", "file" => seed, "details" => {"mode" => mode}}]]}
  checks += 1
  failures += expect("a chain that does not start at a seed", refused?(unseeded, tmp + "/bad-unseeded"), true)
  midway = {"chains" => [[root, {"kind" => "closure", "file" => tmp + "/basis.mfw", "details" => {"recipe" => recipe}}]]}
  checks += 1
  failures += expect("a seed kind in mid-chain", refused?(midway, tmp + "/bad-midway"), true)
  missing = {"chains" => [[{"kind" => "closure", "file" => tmp + "/no-such-file.mfw", "details" => {"recipe" => recipe}}]]}
  checks += 1
  failures += expect("a file that is not there", refused?(missing, tmp + "/bad-missing"), true)

if failures > 0
  << "FAIL " + failures.to_s + " of " + checks.to_s + " lineage build checks"
  exit(1)
<< "PASS gf2 lineage build: " + checks.to_s + " checks"
