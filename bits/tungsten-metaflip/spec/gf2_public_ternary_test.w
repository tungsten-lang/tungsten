# The public-scheme import (lib/metaflip/gf2/public_ternary.w) against the Python original
# (tools/screen_public_ternary_gf2.py): the parity of exact and rational coefficients, the walker's result line, the
# choice of files within best + alternatives, the seeds and manifest written for six option sets over a scheme tree with
# accepted, rejected, duplicate, cancelling and skipped files, and the walks driven through a stand-in walker. The
# goldens in spec/fixtures/gf2_public_ternary/expected come from the original (generate.py runs it); the tree is
# committed here as one commit with fixed author and date, so its hash is the golden one. Prints FAIL lines and exits 1
# on a mismatch.
use core/system
use ../lib/metaflip/gf2/public_ternary
use ../lib/metaflip/gf2/jsonx
use ../lib/metaflip/gf2/procx
use ../lib/metaflip/gf2/fsx
use ../lib/metaflip/gf2/gitx
use ../lib/metaflip/gf2/textx

failures = 0 ## i64
checks = 0 ## i64

fixtures = __DIR__ + "/fixtures/gf2_public_ternary"
golden = fixtures + "/expected"
url = "https://example.invalid/fixture-schemes"

-> expect(label, got, want)
  if got != want
    if type(got) == "Array" && type(want) == "Array"
      at = 0
      at += 1 while at < got.size && at < want.size && got[at] == want[at]
      << "FAIL " + label + ": " + got.size.to_s + " against " + want.size.to_s + " entries, first difference at " + at.to_s
      << "  got  " + (at < got.size ? got[at].to_s : "-")
      << "  want " + (at < want.size ? want[at].to_s : "-")
    else
      << "FAIL " + label + ": got " + got.to_s.slice(0, 160) + " want " + want.to_s.slice(0, 160)
    return 1
  0

-> lines_of(text)
  text.split("\n").select(-> (line) line != "")

# splitlines: the physical lines of a text that ends in a newline, blank ones included
-> physical_lines(text)
  parts = text.split("\n")
  parts.pop if parts.size > 0 && parts.last == ""
  parts

# ---- parity ----------------------------------------------------------------------------------------

lines_of(read_file(golden + "/parity.tsv")).each -> (line)
  fields = line.split("\t")
  outcome = nil
  begin
    outcome = "ok " + Metaflip:Gf2:PublicTernary.parity(Jsonx.loads(fields[0])).to_s
  rescue e: SchemeRejected
    outcome = "error " + e.message
  checks += 1
  failures += expect("parity " + fields[0], outcome, fields[1])

# ---- the walker's result line ------------------------------------------------------------------------

lines_of(read_file(golden + "/parse_result.tsv")).each -> (line)
  fields = line.split("\t")
  found = Metaflip:Gf2:PublicTernary.parse_result(Jsonx.loads(fields[0]))
  checks += 1
  failures += expect("parse_result " + fields[0], found == nil ? "none" : found.map(-> (n) n.to_s).join(" "), fields[1])

# ---- a scheme tree as one commit -----------------------------------------------------------------------

git_env = {"GIT_AUTHOR_NAME" => "fixture", "GIT_AUTHOR_EMAIL" => "fixture@example.invalid", "GIT_COMMITTER_NAME" => "fixture", "GIT_COMMITTER_EMAIL" => "fixture@example.invalid", "GIT_AUTHOR_DATE" => "2026-09-30T12:00:00+0000", "GIT_COMMITTER_DATE" => "2026-09-30T12:00:00+0000", "GIT_CONFIG_GLOBAL" => "/dev/null", "GIT_CONFIG_SYSTEM" => "/dev/null"}

-> git_in(repo, env, args)
  Procx.check_output(["git", "-C", repo] + args, env: env)

# name => [alternatives, rational] of the option sets the goldens were made with
runs = {
  "default" => {"min_dim" => 2, "min_max_dim" => 2, "max_dim" => 16, "rational" => false, "alternatives" => 0},
  "alternatives" => {"min_dim" => 2, "min_max_dim" => 2, "max_dim" => 16, "rational" => false, "alternatives" => 1},
  "rational" => {"min_dim" => 2, "min_max_dim" => 2, "max_dim" => 16, "rational" => true, "alternatives" => 0},
  "rational_alternatives" => {"min_dim" => 2, "min_max_dim" => 2, "max_dim" => 16, "rational" => true, "alternatives" => 2},
  "everything" => {"min_dim" => 2, "min_max_dim" => 2, "max_dim" => 16, "rational" => true, "alternatives" => 10},
  "window" => {"min_dim" => 2, "min_max_dim" => 3, "max_dim" => 8, "rational" => true, "alternatives" => 1}
}

Fsx.with_tempdir(prefix: "gf2-public-ternary-") -> (tmp)
  repo = tmp + "/repo"
  Procx.check_output(["cp", "-R", fixtures + "/tree", repo])
  git_in(repo, git_env, ["init", "-q"])
  git_in(repo, git_env, ["add", "-f", "."])
  git_in(repo, git_env, ["commit", "-q", "-m", "fixture"])
  git = Gitx.new(repo)
  checks += 1
  failures += expect("revision", git.rev_parse("HEAD"), read_file(golden + "/revision.txt").strip)

  # which files, by (alternatives, rational)
  wanted = Jsonx.load(golden + "/integer_files.json")
  [[0, false], [1, false], [1, true], [2, true]].each -> (pair)
    key = pair[0].to_s + "," + (pair[1] ? "True" : "False")
    files = Metaflip:Gf2:PublicTernary.integer_files(git, "HEAD", pair[0], pair[1])
    checks += 1
    failures += expect("integer_files " + key + " shapes", files.keys.sort, wanted[key].keys.sort)
    wanted[key].each -> (shape, items)
      checks += 1
      failures += expect("integer_files " + key + " " + shape, Jsonx.dumps(files[shape]), Jsonx.dumps(items))

  # seeds
  runs.each -> (name, options)
    out = tmp + "/out-" + name
    summary = Metaflip:Gf2:PublicTernary.seeds(repo, "HEAD", url, out, options)
    want = golden + "/runs/" + name
    checks += 1
    failures += expect(name + " summary", summary, read_file(want + "/summary.txt").strip)
    checks += 1
    failures += expect(name + " seeds.json", read_file(out + "/seeds.json").replace(tmp + "/", ""), read_file(want + "/seeds.json"))
    listing = []
    Fsx.entries(out).each -> (file)
      listing.push(file + "\t" + Digest.sha256(read_file(out + "/" + file))) if file.ends_with?(".mfw")
    checks += 1
    failures += expect(name + " seed files", listing, lines_of(read_file(want + "/mfw.tsv")))
    checks += 1
    refused = false
    begin
      Metaflip:Gf2:PublicTernary.seeds(repo, "HEAD", url, out, options)
    rescue e: FsError
      refused = true
    failures += expect(name + " existing output directory is refused", refused, true)

  # walks, through a stand-in walker that obeys the seed's file name
  stub = tmp + "/walker_stub.sh"
  write_file(stub, read_file(fixtures + "/walker_stub.sh"))
  Procx.check_output(["chmod", "755", stub])
  manifest = Jsonx.load(tmp + "/out-alternatives/seeds.json")
  picks = []
  manifest["seeds"].each_with_index -> (row, index)
    tag = ["ok", "drop", "fail", "noline", "ok"][index % 5]
    source = tmp + "/out-alternatives/" + Fsx.basename(row["mfw"])
    renamed = tmp + "/out-alternatives/" + tag + "-" + Fsx.basename(source)
    write_file(renamed, read_file(source))
    copied = {}
    row.each -> (key, value)
      copied[key] = value if key != "mfw_sha256" || index != 4
    copied["mfw"] = renamed
    picks.push(copied)
  Fsx.write(tmp + "/walk-manifest.json", Jsonx.dumps({"schema" => 1, "seeds" => picks}))
  progress = []
  options = {"walker" => stub, "out" => tmp + "/walk.jsonl", "steps" => 5000, "jobs" => 3, "repeats" => 2, "nonce_base" => 17, "min_rank" => 0, "largest_first" => false, "lines" => progress}
  Metaflip:Gf2:PublicTernary.walk(tmp + "/walk-manifest.json", options)
  # the output of a seed without a hash is named after the hash of its path, which depends on the temporary directory
  path_tag = Digest.sha256(picks[4]["mfw"]).slice(0, 8)
  checks += 1
  failures += expect("walk log", lines_of(read_file(tmp + "/walk.jsonl").replace(path_tag, "$PATHSHA").replace(tmp, "$TMP")).sort, lines_of(read_file(golden + "/walk.tsv")))
  # what the tool prints: each progress line and a newline (an error text already ends in one)
  printed = progress.map(-> (line) line + "\n").join("").replace(path_tag, "$PATHSHA").replace(tmp, "$TMP")
  checks += 1
  failures += expect("walk progress", physical_lines(printed).sort, physical_lines(read_file(golden + "/walk_stdout.txt")))
  produced = []
  Fsx.entries(tmp + "/walk_mfw").each -> (file)
    produced.push((file + "\t" + Digest.sha256(read_file(tmp + "/walk_mfw/" + file))).replace(path_tag, "$PATHSHA"))
  checks += 1
  failures += expect("walk outputs", produced, lines_of(read_file(golden + "/walk_outputs.tsv")))
  # a second run finds every walk in the log and starts none
  again = []
  options["lines"] = again
  Metaflip:Gf2:PublicTernary.walk(tmp + "/walk-manifest.json", options)
  checks += 1
  failures += expect("walk resume", again, ["0 walks queued"])

if failures > 0
  << "FAIL " + failures.to_s + " of " + checks.to_s + " public ternary checks"
  exit(1)
<< "PASS gf2 public ternary: " + checks.to_s + " checks"
