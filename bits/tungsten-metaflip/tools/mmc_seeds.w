# matmulcatalog recipes -> exact GF(2) seeds, with attribution.
# Port of tools/mmc_gf2_seeds.py; the library is lib/metaflip/gf2/catalogue_seeds.w (its header says what each seed row carries).
#
#   mmc_seeds targets --clone CLONE [--revision REV] [--cache-dir DIR] --lille FMM_SOTA.JSON [--fmm-repo CLONE]
#                     [--fmm-revision REV] [--extra-repo DIR]... --board SCOREBOARD.JSON [--slack N] [--min-dim N] --out TARGETS.JSON
#   mmc_seeds replay  --clone CLONE [--revision REV] [--cache-dir DIR] --targets TARGETS.JSON --out DIR [--board SCOREBOARD.JSON]
#                     [--allow-nonf2] [--retry-failed] [--only NAME...] [--jobs N]
#
# targets: choose catalogue schemes worth replaying: stamped F2, not commutative, rank at most the best rank the other sources
#          list (+ SLACK), and nothing on our scoreboard at or below that rank.
# replay:  materialize the targets over GF(2), verify each against the complete matrix-multiplication tensor, and write MFW1 seeds,
#          results.jsonl (one row per target, resumed on the next run) and seeds.json (valid input for `public_ternary walk`).
#          The targets are replayed one after the other; --jobs is accepted and ignored.
#
# Run as `bin/tungsten run tools/mmc_seeds.w -- ARGS` or compile with `-o`.
use core/system
use ../lib/metaflip/gf2/cli
use ../lib/metaflip/gf2/catalogue_seeds

parser = Cli.new("mmc_seeds.w", description: "matmulcatalog recipes -> exact GF(2) seeds, with attribution.")
commands = parser.subcommands(dest: "command", required: true)

targets = commands.command("targets", help: "select catalogue schemes worth replaying")
targets.add("--clone", required: true, help: "local matmulcatalog clone (a partial clone works)")
targets.add("--revision", default: "HEAD", help: "pinned catalogue revision (recorded per seed)")
targets.add("--cache-dir", default: "mmc-cache")
targets.add("--lille", required: true, help: "fmm_digest fmm_sota.json")
targets.add("--fmm-repo", help: "FastMatrixMultiplication clone")
targets.add("--fmm-revision", default: "HEAD")
targets.add("--extra-repo", action: :append, default: [])
targets.add("--board", required: true, help: "scoreboard JSON from gf2_record_board --json")
targets.add("--slack", type: :int, default: 0, help: "also accept ranks up to best listed + SLACK")
targets.add("--min-dim", type: :int, default: 2)
targets.add("--out", required: true)

replay = commands.command("replay", help: "materialize targets over GF(2) into exact seeds")
replay.add("--clone", required: true, help: "local matmulcatalog clone (a partial clone works)")
replay.add("--revision", default: "HEAD", help: "pinned catalogue revision (recorded per seed)")
replay.add("--cache-dir", default: "mmc-cache")
replay.add("--targets", required: true)
replay.add("--out", required: true)
replay.add("--board", help: "scoreboard JSON: exact local witnesses may serve as leaves")
replay.add("--allow-nonf2", action: :store_true, help: "diagnostics: also replay non-F2 schemes")
replay.add("--retry-failed", action: :store_true)
replay.add("--only", nargs: "*", help: "canonical shapes or catalogue files to replay")
replay.add("--jobs", type: :int, default: 1, help: "accepted and ignored: targets are replayed one after the other")

args = parser.parse(argv())
if args["command"] == "targets"
  options = {"clone" => args["clone"], "revision" => args["revision"], "cache_dir" => args["cache_dir"], "lille" => args["lille"], "fmm_repo" => args["fmm_repo"], "fmm_revision" => args["fmm_revision"], "extra_repo" => args["extra_repo"], "board" => args["board"], "slack" => args["slack"], "min_dim" => args["min_dim"], "out" => args["out"]}
  << CatalogueSeeds.select_targets(options)
else
  ccall("w_eputs", "mmc_seeds: --jobs is ignored: the targets are replayed one after the other") if args["jobs"] > 1
  options = {"clone" => args["clone"], "revision" => args["revision"], "cache_dir" => args["cache_dir"], "targets" => args["targets"], "out" => args["out"], "board" => args["board"], "allow_nonf2" => args["allow_nonf2"], "retry_failed" => args["retry_failed"], "only" => args["only"]}
  CatalogueSeeds.replay(options)
