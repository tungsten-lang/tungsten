# Bounded exact GF(2) projection/basis/walk search for multiword rectangles.
# Port of tools/search_wide_projection_walks.py; the library is lib/metaflip/gf2/projection_walks.w (its header says what is checked).
#
#   projection_walks --seed SEED.mfw --digest FMM_SOTA.JSON [--walker BINARY --output-dir DIR] [--depth N] [--beam N]
#                    [--steps N] [--nonce-base N] [--list-only] [--no-ruby]
#
# From one exact parent, every coordinate projection of the parent (and of its two-pass basis rewrites) is a candidate child; the
# --beam best children, distinct shapes first, are walked with the compiled directed walker (tools/wide_rect_walk.w) and the results
# are verified and, for --depth above one, become the parents of the next level. The public ranks of --digest schedule only; every
# parent, child and result is checked against the complete tensor (and by tools/verify_tensor.rb unless --no-ruby). --list-only prints
# the selected children of the seed and walks nothing. Walks are deterministic in (seed, steps, nonce).
#
# Run as `bin/tungsten run tools/projection_walks.w -- ARGS` or compile with `-o`.
use core/system
use ../lib/metaflip/gf2/cli
use ../lib/metaflip/gf2/projection_walks

parser = Cli.new("projection_walks.w", description: "Bounded exact GF(2) projection/basis/walk search for multiword rectangles.")
parser.add("--seed", type: :path, required: true)
parser.add("--digest", type: :path, required: true, help: "dated rank table for scheduling only")
parser.add("--walker", type: :path)
parser.add("--output-dir", type: :path)
parser.add("--depth", type: :int, default: 1)
parser.add("--beam", type: :int, default: 2)
parser.add("--steps", type: :int, default: 100000000)
parser.add("--nonce-base", type: :int, default: 19071)
parser.add("--list-only", action: :store_true)
parser.add("--no-ruby", action: :store_true, help: "skip tools/verify_tensor.rb (both gates of the Tungsten verifier remain)")
args = parser.parse(argv())
parser.error("depth, beam, and steps must be positive and bounded") if args["depth"] < 1 || args["beam"] < 1 || args["steps"] < 1 || args["steps"] > 1000000000
parser.error("nonce base outside native range") if args["nonce_base"] < 1 || args["nonce_base"] > 2147483647
parser.error("--walker and --output-dir are required for walks") if !args["list_only"] && (args["walker"] == nil || args["output_dir"] == nil)
verifier = args["no_ruby"] ? nil : __DIR__ + "/verify_tensor.rb"
options = {"seed" => args["seed"], "digest" => args["digest"], "walker" => args["walker"], "output_dir" => args["output_dir"], "depth" => args["depth"], "beam" => args["beam"], "steps" => args["steps"], "nonce_base" => args["nonce_base"], "list_only" => args["list_only"], "verifier" => verifier}
ProjectionWalks.run(options)
