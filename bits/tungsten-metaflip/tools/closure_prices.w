# Rank-only GF(2) closure over verified board witnesses (a price, NOT a witness). Port of the campaign's closure.py.
#
#   closure_prices --lille FMM_SOTA.json --matmulcatalog CATALOG.json --fmm-repo CLONE [--fmm-revision REV]
#                  [--extra-repo DIR] [--board BOARD.json] [--out LEADS.json] [--tol FRACTION]
#
# price(s) = min(witness rank, naive n*m*p, block split along any axis, componentwise Kronecker product of two smaller shapes),
# for every sorted shape up to 32. Lists the shapes whose price is within `tol` of the best listed rank (or below it) and
# improves the board, with the recipe. `tol` defaults to the environment variable CLOSURE_TOL, else 0. The tables are those of
# gf2_record_board.w; the board is a file written by it (default board_0929.json).
#
# Run as `bin/tungsten run tools/closure_prices.w -- ARGS` or compile with `-o`.
use ../lib/metaflip/gf2/cli
use ../lib/metaflip/gf2/closure_prices

parser = Cli.new("closure_prices.w", description: "Rank-only GF(2) closure over verified board witnesses (a price, not a witness).")
parser.add("--lille", required: true)
parser.add("--matmulcatalog")
parser.add("--fmm-repo")
parser.add("--fmm-revision", default: "HEAD")
parser.add("--extra-repo", action: :append, default: [])
parser.add("--board", default: "board_0929.json")
parser.add("--out", default: "closure_leads.json")
parser.add("--tol", help: "fraction of the listed rank the price may exceed (default: $CLOSURE_TOL or 0)")
args = parser.parse(argv())

tol_text = args["tol"]
tol_text = env("CLOSURE_TOL") if tol_text == nil
tol_text = "0" if tol_text == nil || tol_text == ""
tol = Floatx.parse(tol_text)
max = 32
tables = Metaflip:Gf2:RecordBoard.public_tables(args["lille"], args["matmulcatalog"], args["fmm_repo"], args["fmm_revision"], args["extra_repo"])
board = {}
Jsonx.load(args["board"]).each -> (row)
  board[row["shape"]] = row["rank"]
board = Metaflip:Gf2:ClosurePrices.board_with_leaves(board, max)
computed = Metaflip:Gf2:ClosurePrices.compute(board, max)
rows = Metaflip:Gf2:ClosurePrices.leads(computed, board, tables[1], tol, max)
<< rows.size.to_s + " shapes where the closure price is within " + Floatx.percent(tol, 1) + " of the listed rank (or below) and improves the board"
rows.slice(0, 60).each -> (row)
  << Metaflip:Gf2:ClosurePrices.row_text(row)
records = rows.map -> (row)
  {"shape" => row[1], "price" => row[2], "lille" => row[3], "board" => row[4], "recipe" => row[5]}
Fsx.write(args["out"], Jsonx.dumps(records, indent: 1))
