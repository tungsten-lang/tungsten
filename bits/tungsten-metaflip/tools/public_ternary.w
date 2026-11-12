# Screen public integer-coefficient schemes for GF(2)-only rank reductions.
# Port of tools/screen_public_ternary_gf2.py; the library is lib/metaflip/gf2/public_ternary.w.
#
#   public_ternary seeds --repo CLONE [--revision REV] [--url URL] --out DIR [--min-dim N] [--min-max-dim N]
#                        [--max-dim N] [--include-rational] [--alternatives N]
#   public_ternary walk  --seeds DIR/seeds.json --walker BINARY --out LOG.jsonl [--steps N] [--jobs N]
#                        [--repeats N] [--nonce-base N] [--min-rank N] [--largest-first]
#
# seeds: converts every distinct integer scheme at each shape's best integer rank (or within best + N) of a
#        FastMatrixMultiplication-format repository into an MFW1 seed, every one passing the GF(2) tensor expansion.
# walk:  runs the compiled finite directed walker (tools/wide_rect_walk.w) over the seeds in parallel and appends
#        one JSON row per walk; walks are deterministic in (seed, steps, nonce), so each row is replayable.
#
# Run as `bin/tungsten run tools/public_ternary.w -- ARGS` or compile with `-o`.
use core/system
use ../lib/metaflip/gf2/cli
use ../lib/metaflip/gf2/public_ternary

parser = Cli.new("public_ternary.w", description: "Screen public integer-coefficient schemes for GF(2)-only rank reductions.")
commands = parser.subcommands(dest: "command", required: true)

seeds = commands.command("seeds", help: "convert public integer schemes to exact GF(2) seeds")
seeds.add("--repo", required: true, help: "local (partial) clone in FastMatrixMultiplication format")
seeds.add("--revision", default: "HEAD")
seeds.add("--url", help: "canonical repository URL recorded in the manifest")
seeds.add("--out", required: true, help: "new output directory")
seeds.add("--min-dim", type: :int, default: 2)
seeds.add("--min-max-dim", type: :int, default: 5, help: "skip shapes whose largest side is smaller")
seeds.add("--max-dim", type: :int, default: 16)
seeds.add("--include-rational", action: :store_true, help: "also try _Q files; only odd-denominator schemes pass the parity gate")
seeds.add("--alternatives", type: :int, default: 0, help: "also convert every integer file within best+N (distinct GF(2) seeds only)")

walk = commands.command("walk", help: "directed GF(2) walks from converted seeds")
walk.add("--seeds", required: true)
walk.add("--walker", required: true, help: "compiled tools/wide_rect_walk.w")
walk.add("--out", required: true, help: "JSONL log (appended; finished walks are skipped)")
walk.add("--steps", type: :int, default: 40000000)
walk.add("--jobs", type: :int, default: System.cpu_count - 2 < 1 ? 1 : System.cpu_count - 2)
walk.add("--repeats", type: :int, default: 1, help: "independent nonces per seed")
walk.add("--nonce-base", type: :int, default: 1)
walk.add("--min-rank", type: :int, default: 0)
walk.add("--largest-first", action: :store_true, help: "queue high-rank seeds first")

args = parser.parse(argv())
if args["command"] == "seeds"
  options = {"min_dim" => args["min_dim"], "min_max_dim" => args["min_max_dim"], "max_dim" => args["max_dim"], "rational" => args["include_rational"], "alternatives" => args["alternatives"]}
  << Metaflip:Gf2:PublicTernary.seeds(args["repo"], args["revision"], args["url"], args["out"], options)
else
  options = {"walker" => args["walker"], "out" => args["out"], "steps" => args["steps"], "jobs" => args["jobs"], "repeats" => args["repeats"], "nonce_base" => args["nonce_base"], "min_rank" => args["min_rank"], "largest_first" => args["largest_first"]}
  Metaflip:Gf2:PublicTernary.walk(args["seeds"], options)
