# Scoreboard: best exactly verified local GF(2) witness per shape vs public ranks.
# Port of tools/gf2_record_board.py; the library is lib/metaflip/gf2/record_board.w.
#
#   gf2_record_board --lille FMM_SOTA.json [--matmulcatalog CATALOG.json]
#                    [--fmm-repo CLONE [--fmm-revision REV]] [--extra-repo DIR]...
#                    --witness FILE_OR_DIR [--witness ...] [--cache CACHE.json]
#                    [--json ROWS.json] [-v]
#
# Every counted witness is expanded against the full matrix-multiplication tensor by two
# independent gates; the verdicts are cached by SHA-256 of the file. A witness is classified
# below_all (beats every listed rank in any ring), gf2_valid_only (beats every listed
# GF(2)-valid scheme but a Q/C-only rank is lower), tie, above or no_public_rank. A listed
# rank is a comparison, never a certificate.
#
# Run as `bin/tungsten run tools/gf2_record_board.w -- ARGS` or compile with `-o`.
use ../lib/metaflip/gf2/cli
use ../lib/metaflip/gf2/record_board

parser = Cli.new("gf2_record_board.w", description: "Scoreboard: best exactly verified local GF(2) witness per shape vs public ranks.")
parser.add("--lille", required: true)
parser.add("--matmulcatalog")
parser.add("--fmm-repo")
parser.add("--fmm-revision", default: "HEAD")
parser.add("--extra-repo", action: :append, default: [])
parser.add("--witness", action: :append, required: true, help: "file or directory (repeatable)")
parser.add("--cache", help: "JSON verification cache keyed by SHA-256")
parser.add("--jobs", type: :int, default: 8, help: "accepted for compatibility with the Python tool; witnesses are verified one after the other")
parser.add("--json", help: "write every row here")
parser.add("--verbose", short: "-v", action: :store_true)
args = parser.parse(argv())

cache = {}
if args["cache"] != nil && File.exists?(args["cache"])
  cache = Jsonx.load(args["cache"])
ours = Metaflip:Gf2:RecordBoard.witnesses(args["witness"], cache)
Fsx.write(args["cache"], Jsonx.dumps(cache)) if args["cache"] != nil
tables = Metaflip:Gf2:RecordBoard.public_tables(args["lille"], args["matmulcatalog"], args["fmm_repo"], args["fmm_revision"], args["extra_repo"])
rows = Metaflip:Gf2:RecordBoard.rows(ours, tables)
Fsx.write(args["json"], Jsonx.dumps(rows, indent: 1) + "\n") if args["json"] != nil
<< Metaflip:Gf2:RecordBoard.summary(rows)
if args["verbose"]
  Metaflip:Gf2:RecordBoard.verbose_lines(rows).each -> (line)
    << line
