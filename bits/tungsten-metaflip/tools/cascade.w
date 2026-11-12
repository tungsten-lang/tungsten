# The drivers of the record hunt's cascade: parents, projection screen, child selection, walk screen, iterative deepening.
# Ports of the campaign's scripts next_parents.py, project_screen.py, pick_children.py, sweep.py and iterate.py (tools/campaign/);
# the library is lib/metaflip/gf2/cascade.w (its header says how the port differs).
#
#   cascade parents BOARD.json OUT.json PROJ.jsonl... [--kinds below_all,gf2_valid_only]
#   cascade screen  SEEDS.json OUT.jsonl [--jobs N] --mfw-dir DIR --lille FMM_SOTA.JSON [--catalog CATALOG.JSON] [--fmm-repo CLONE] [--fmm-revision REV] [--extra-repo DIR]...
#   cascade pick    PROJ.jsonl BOARD.json OUT.json --lille FMM_SOTA.JSON [--catalog ...] [--fmm-repo ...] [--fmm-revision ...] [--extra-repo ...] [--tolerance 0.03]
#   cascade sweep   SEEDS.json OUT.jsonl --walker BINARY --steps N [--jobs N] [--nonce-base N] [--filter FILE] [--repeats N]
#   cascade iterate SEEDS.json LOG.jsonl --walker BINARY --steps N [--walks-per-round N] [--patience N] [--jobs N] [--nonce-base N]
#
# parents: the witnesses of the scoreboard (a `gf2_record_board --json` file) of the given kinds that no PROJ log has projected yet.
# screen:  the projection children (13 bases) of every parent, as MFW1 files in --mfw-dir and one JSON row per child in OUT.jsonl;
#          every parent is screened by a process of its own (this program, `screen-one`), --jobs at a time.
# pick:    per child shape the lowest-rank projection that beats our witness and is within the tolerance above the best listed rank.
# sweep:   the compiled directed walker (tools/wide_rect_walk.w) over exact seeds, --jobs at a time; rows appended to OUT.jsonl.
# iterate: walk each seed's current best until --patience rounds in a row do not lower the rank.
#
# Run as `bin/tungsten run tools/cascade.w -- ARGS` or compile with `-o`.
use core/system
use ../lib/metaflip/gf2/cli
use ../lib/metaflip/gf2/cascade
use ../lib/metaflip/gf2/jsonx

parser = Cli.new("cascade.w", description: "The drivers of the record hunt's cascade.")
commands = parser.subcommands(dest: "command", required: true)

parents = commands.command("parents", help: "scoreboard witnesses that no projection log has covered")
parents.add("board", type: :path)
parents.add("out", type: :path)
parents.add("logs", type: :path, nargs: "*")
parents.add("--kinds", default: "below_all,gf2_valid_only", help: "comma-separated scoreboard kinds")

screen = commands.command("screen", help: "projection children of every parent")
screen.add("seeds", type: :path)
screen.add("out", type: :path)
screen.add("--mfw-dir", required: true, help: "where the children are written")
screen.add("--lille", required: true, help: "fmm_digest fmm_sota.json")
screen.add("--catalog", help: "matmulcatalog docs/catalog.json, one more source of listed ranks")
screen.add("--fmm-repo", help: "FastMatrixMultiplication clone")
screen.add("--fmm-revision", default: "HEAD")
screen.add("--extra-repo", action: :append, default: [])
screen.add("--jobs", type: :int, default: 1, help: "parents screened at once, each by a process of its own")

# internal: what `screen` runs for one parent; prints the rows of its children as one JSON array
one = commands.command("screen-one", help: "(internal) projection children of one parent, as JSON")
one.add("parent", type: :path)
one.add("--mfw-dir", required: true)
one.add("--lille", required: true)
one.add("--catalog")
one.add("--fmm-repo")
one.add("--fmm-revision", default: "HEAD")
one.add("--extra-repo", action: :append, default: [])

pick = commands.command("pick", help: "projection children worth walking")
pick.add("proj", type: :path)
pick.add("board", type: :path)
pick.add("out", type: :path)
pick.add("--lille", required: true, help: "fmm_digest fmm_sota.json")
pick.add("--catalog", help: "matmulcatalog docs/catalog.json, one more source of listed ranks")
pick.add("--fmm-repo", help: "FastMatrixMultiplication clone")
pick.add("--fmm-revision", default: "HEAD")
pick.add("--extra-repo", action: :append, default: [])
pick.add("--tolerance", default: "0.03", help: "how far above the best listed rank a child may be (a fraction)")

sweep = commands.command("sweep", help: "parallel directed-walk screen over exact seeds")
sweep.add("seeds", type: :path)
sweep.add("out", type: :path)
sweep.add("--walker", required: true, help: "compiled tools/wide_rect_walk.w")
sweep.add("--steps", type: :int, required: true)
sweep.add("--jobs", type: :int, default: 4)
sweep.add("--nonce-base", type: :int, default: 1)
sweep.add("--filter", help: "file of shapes (or canonical shapes) to walk")
sweep.add("--repeats", type: :int, default: 1)

iterate = commands.command("iterate", help: "iterative deepening of each seed")
iterate.add("seeds", type: :path)
iterate.add("log", type: :path)
iterate.add("--walker", required: true, help: "compiled tools/wide_rect_walk.w")
iterate.add("--steps", type: :int, required: true)
iterate.add("--walks-per-round", type: :int, default: 2)
iterate.add("--patience", type: :int, default: 2)
iterate.add("--jobs", type: :int, default: 4)
iterate.add("--nonce-base", type: :int, default: 1)

args = parser.parse(argv())
command = args["command"]
tables = {"lille" => args["lille"], "catalog" => args["catalog"], "fmm_repo" => args["fmm_repo"], "fmm_revision" => args["fmm_revision"], "extra_repo" => args["extra_repo"]}
if command == "parents"
  << Cascade.next_parents(args["board"], args["out"], args["logs"], args["kinds"].split(","))
elsif command == "screen"
  tables["mfw_dir"] = args["mfw_dir"]
  tables["jobs"] = args["jobs"]
  tables["worker"] = [System.executable_path, "screen-one"]
  Cascade.project_screen(args["seeds"], args["out"], tables)
elsif command == "screen-one"
  tables["mfw_dir"] = args["mfw_dir"]
  << Jsonx.dumps(Cascade.screen_one({"mfw" => args["parent"]}, Cascade.public_ranks(tables), tables))
elsif command == "pick"
  << Cascade.pick_children(args["proj"], args["board"], args["out"], args["tolerance"], tables)
elsif command == "sweep"
  Cascade.sweep(args["seeds"], args["out"], {"walker" => args["walker"], "steps" => args["steps"], "jobs" => args["jobs"], "nonce_base" => args["nonce_base"], "filter" => args["filter"], "repeats" => args["repeats"]})
else
  Cascade.iterate(args["seeds"], args["log"], {"walker" => args["walker"], "steps" => args["steps"], "walks_per_round" => args["walks_per_round"], "patience" => args["patience"], "jobs" => args["jobs"], "nonce_base" => args["nonce_base"]})
