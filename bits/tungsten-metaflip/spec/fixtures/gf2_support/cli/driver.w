# A real command line built on lib/metaflip/gf2/cli.w: the option set of
# tools/gf2_record_board.py.  spec/gf2_support/cli_cases.w runs it as a child process
# to check what only a process shows (exit status, the stream each text goes to), and
# compares the printed Hash with Python's Namespace for the same argv.
#
#   tungsten run driver.w -- --lille L --witness a --witness b --jobs 3 -v
use ../../../../lib/metaflip/gf2/cli
use core/json

parser = Cli.new("gf2_record_board.py", description: "Scoreboard: best exactly verified local GF(2) witness per shape vs public ranks.")
parser.add("--lille", required: true)
parser.add("--matmulcatalog")
parser.add("--fmm-repo")
parser.add("--fmm-revision", default: "HEAD")
parser.add("--extra-repo", action: :append, default: [])
parser.add("--witness", action: :append, required: true, help: "file or directory (repeatable)")
parser.add("--cache", help: "JSON verification cache keyed by SHA-256")
parser.add("--jobs", type: :int, default: 6, help: "processes for verifying new witness files")
parser.add("--json", help: "write every row here")
parser.add("--verbose", short: "-v", action: :store_true)

args = parser.parse(argv())
parser.error("--json needs --cache") if args["json"] != nil && args["cache"] == nil
<< JSON.encode(args)
