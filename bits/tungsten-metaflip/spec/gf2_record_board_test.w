# The scoreboard library against the Python original: the name parsers, the verdict for every witness
# format, the FMM file-name table, and the whole board on a small tree (rows, cache, summary and the -v
# lines). The goldens in spec/fixtures/gf2_record_board/expected come from tools/gf2_record_board.py
# (spec/fixtures/gf2_record_board/generate.py runs it). Prints FAIL lines and exits 1 on a mismatch.
use core/system
use ../lib/metaflip/gf2/record_board

failures = 0 ## i64
checks = 0 ## i64

-> expect(label, got, want) i64
  if got != want
    << "FAIL " + label + ": got " + got.to_s + " want " + want.to_s
    return 1
  0

fixtures = __DIR__ + "/fixtures/gf2_record_board"
input = fixtures + "/in"
expected = fixtures + "/expected"

-> golden(name)
  text = read_file(fixtures + "/expected/" + name)
  raise "missing golden " + name if text == nil
  text

# Rows of a tab-separated golden.
-> rows_of(name)
  golden(name).split("\n").select(-> (line) line != "").map(-> (line) line.split("\t"))

# 1. re.search(r'(\d+)x(\d+)(?:x(\d+))?', name)
rows_of("dims.tsv").each -> (row)
  checks += 1
  want = row[1]
  got = Jsonx.dumps(Metaflip:Gf2:RecordBoard.find_dims(row[0]))
  failures += expect("find_dims of " + row[0], got, want)

# 2. the FMM file-name pattern, with the tool's exclusion of `/known/`
rows_of("ring.tsv").each -> (row)
  checks += 1
  name = row[0]
  entry = name.include?("/known/") ? nil : Metaflip:Gf2:RecordBoard.ring_entry(name)
  got = entry == nil ? "None" : entry.join("\t")
  want = row[1] == "None" ? "None" : row[1..3].join("\t")
  failures += expect("ring_entry of " + name, got, want)

names = rows_of("ring.tsv").map(-> (row) row[0])
checks += 1
failures += expect("fmm_ranks", Jsonx.dumps(Metaflip:Gf2:RecordBoard.fmm_ranks(names), indent: 1, sort_keys: true) + "\n", golden("fmm_ranks.json"))

# 3. the verdict of decode for every witness file
rows_of("decode.tsv").each -> (row)
  checks += 1
  path = input + "/" + row[0]
  text = Metaflip:Gf2:RecordBoard.load(path)
  verdict = text == nil ? nil : Metaflip:Gf2:RecordBoard.decode(path, text)
  got = verdict == nil ? "None" : Jsonx.dumps(verdict)
  failures += expect("decode of " + row[0], got, row[1])

# 4. the board on the whole tree
cache = {}
ours = Metaflip:Gf2:RecordBoard.witnesses([input + "/witnesses"], cache)
tables = Metaflip:Gf2:RecordBoard.public_tables(input + "/lille.json", input + "/catalog.json", nil, nil, [input + "/extra"])
rows = Metaflip:Gf2:RecordBoard.rows(ours, tables)
checks += 1
failures += expect("rows", (Jsonx.dumps(rows, indent: 1) + "\n").replace(input, "@FIX@"), golden("rows.json"))
checks += 1
failures += expect("cache", Jsonx.dumps(cache) + "\n", golden("cache.json"))
checks += 1
failures += expect("summary", Metaflip:Gf2:RecordBoard.summary(rows) + "\n", golden("summary.txt"))
checks += 1
failures += expect("verbose lines", Metaflip:Gf2:RecordBoard.verbose_lines(rows).join("\n").replace(input, "@FIX@") + "\n", golden("verbose.txt"))

# 5. Real data (when GF2_RECORD_HUNT_WORK names the campaign's work directory): the final board of the record
# hunt, recomputed from its own witness ranks and the four public tables at the pinned revisions, is the same file.
work = env("GF2_RECORD_HUNT_WORK")
if work != nil && work != "" && File.exists?(work + "/board_final.json")
  final_text = read_file(work + "/board_final.json")
  ours = {}
  Jsonx.loads(final_text).each -> (row)
    ours[row["shape"]] = [row["rank"], row["path"]]
  tables = Metaflip:Gf2:RecordBoard.public_tables(work + "/upstream/fmm_digest/fmm_sota.json", work + "/mmc_catalog_0929.json", work + "/upstream/fmm", "HEAD", [work + "/upstream/merlijn"])
  checks += 1
  failures += expect("board_final.json from its own witness ranks", Jsonx.dumps(Metaflip:Gf2:RecordBoard.rows(ours, tables), indent: 1) + "\n", final_text)
  << "checked " + ours.size.to_s + " shapes of board_final.json against the four public tables"
else
  << "skip board_final.json (set GF2_RECORD_HUNT_WORK to the campaign work directory)"

if failures > 0
  << "FAIL " + failures.to_s + " of " + checks.to_s + " record board checks"
  exit(1)
<< "PASS gf2 record board: " + checks.to_s + " checks"
