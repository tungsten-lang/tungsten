# Verify a GF(2) lineage bundle: exact tensors, parent links, replayable steps, provenance.
# Port of tools/verify_gf2_lineage.py; the library is lib/metaflip/gf2/lineage.w (its header lists what each row kind is checked for).
#
#   verify_lineage BUNDLE [--replay-walk BINARY] [--replay-max-rank N] [--source NAME=CLONE]... [--repo-root ROOT]
#
# BUNDLE is a directory with `manifest.json` and one `*.mfw.gz.b64` per row. Every tensor is expanded against the complete
# matrix-multiplication tensor by two independent gates; the rows of each kind are re-derived as far as the options allow.
# --no-ruby and --cache-dir are accepted for compatibility with the original's command line and do nothing here.
# Exit status 0 and a PASS line when the bundle verifies; 1 and the reason on standard error otherwise.
#
# Run as `bin/tungsten run tools/verify_lineage.w -- ARGS` or compile with `-o`.
use ../lib/metaflip/gf2/cli
use ../lib/metaflip/gf2/lineage

parser = Cli.new("verify_lineage.w", description: "Verify a GF(2) lineage bundle: exact tensors, parent links, replayable steps, provenance.")
parser.add("bundle", type: :path)
parser.add("--replay-walk", help: "compiled tools/wide_rect_walk.w")
parser.add("--replay-max-rank", type: :int, default: 1000000000, help: "replay only walks whose result has at most this rank")
parser.add("--source", action: :append, default: [], help: "NAME=CLONE for re-derivation")
parser.add("--cache-dir", default: "mmc-cache", help: "matmulcatalog replay cache")
parser.add("--repo-root", type: :path, help: "checkout root for `retained` rows")
parser.add("--no-ruby", action: :store_true, help: "skip the independent Ruby check")
args = parser.parse(argv())

sources = {}
args["source"].each -> (item)
  at = item.index("=")
  parser.error("argument --source: expected NAME=CLONE: " + item) if at == nil
  sources[item.slice(0, at)] = item.slice(at + 1, item.size - at - 1)
options = {"sources" => sources, "repo_root" => args["repo_root"], "replay_walk" => args["replay_walk"], "replay_max_rank" => args["replay_max_rank"]}
result = nil
begin
  result = Metaflip:Gf2:Lineage.verify(args["bundle"], options)
rescue e: LineageError
  ccall("w_eputs", "verify_lineage: " + e.message)
  exit(1)
Metaflip:Gf2:Lineage.lines(result).each -> (line)
  << line
