# Write a GF(2) lineage bundle (see verify_lineage.w) from explicit chain descriptions.
# Port of tools/build_gf2_lineage_bundle.py; the library is lib/metaflip/gf2/lineage.w (`Lineage.build`).
#
#   build_lineage CHAINS.json OUT_DIR
#
# CHAINS.json:
#   {"walker": "bits/tungsten-metaflip/tools/wide_rect_walk.w",      (optional)
#    "chains": [[STEP, ...], ...]}       each chain runs from a seed row to the retained tensor
# STEP: {"kind": "public-mod2|recipe-replay|closure|basis|projection|walk",
#        "file": "path to the MFW1 tensor (MFW1 text, a decimal certificate or .mfw.gz.b64)",
#        "details": {...}}               per-kind fields checked by verify_lineage.w
#
# Shape, rank and SHA-256 come from the tensor itself; a step's parent is the previous step of its chain. Identical
# tensors shared by several chains are stored once, and a tensor reached with different provenance is refused. The
# builder finishes by running the verifier on what it wrote.
#
# Run as `bin/tungsten run tools/build_lineage.w -- ARGS` or compile with `-o`.
use ../lib/metaflip/gf2/lineage

args = argv()
if args.size != 2
  << "usage: build_lineage CHAINS.json OUT_DIR"
  exit(2)
spec = Jsonx.load(args[0])
manifest = nil
begin
  manifest = Metaflip:Gf2:Lineage.build(spec, args[1])
  Metaflip:Gf2:Lineage.verify(args[1], {})
rescue e: LineageError
  ccall("w_eputs", "build_lineage: " + e.message)
  exit(1)
<< manifest["rows"].size.to_s + " rows written to " + args[1]
