# The replay of matmulcatalog recipes over GF(2) (lib/metaflip/gf2/catalogue.w) against the Python original
# (tools/mmc_gf2_replay.py): the parity of coefficients of every kind, and, on a synthetic catalogue checkout (atoms in four
# layouts, recipes that use every operation of the lineage language and every kind of leaf reference, and files that must
# fail), the scheme or the message of each file, its dependencies, the candidates and the best scheme of several shapes, with
# and without the disk cache. The goldens in spec/fixtures/gf2_catalogue/expected are what the original returns (generate.py runs it);
# the tree is committed here with fixed author and date, so its revision is the golden one. With GF2_RECORD_HUNT_WORK naming the
# campaign's work directory it also replays the 71 rederivable catalogue recipes of release bundle A and compares their digests.
# Prints FAIL lines and exits 1 on a mismatch.
use core/system
use ../lib/metaflip/gf2/catalogue
use ../lib/metaflip/gf2/procx
use ../lib/metaflip/gf2/fsx
use ../lib/metaflip/gf2/jsonx
use ../lib/metaflip/gf2/textx

failures = 0 ## i64
checks = 0 ## i64

fixtures = __DIR__ + "/fixtures/gf2_catalogue"
golden = fixtures + "/expected"

-> expect(label, got, want)
  if got != want
    << "FAIL " + label + ": got " + got.to_s.slice(0, 300) + " want " + want.to_s.slice(0, 300)
    return 1
  0

-> lines_of(text)
  text.split("\n").select(-> (line) line != "")

# ---- coefficients -------------------------------------------------------------------------------------

lines_of(read_file(golden + "/parity.tsv")).each -> (line)
  fields = line.split("\t")
  outcome = nil
  begin
    outcome = "ok " + Mmc.parity(Jsonx.loads(fields[0])).to_s
  rescue e: ReplayError
    outcome = "error ReplayError: " + e.message
  rescue e: MmcFailure
    outcome = "error " + e.type_name + ": " + e.type_name + "(" + Textx.repr_str(e.message) + ")"
  checks += 1
  failures += expect("parity " + fields[0], outcome, fields[1])

# ---- the synthetic catalogue -----------------------------------------------------------------------------

git_env = {"GIT_AUTHOR_NAME" => "fixture", "GIT_AUTHOR_EMAIL" => "fixture@example.invalid", "GIT_COMMITTER_NAME" => "fixture", "GIT_COMMITTER_EMAIL" => "fixture@example.invalid", "GIT_AUTHOR_DATE" => "2026-09-30T12:00:00+0000", "GIT_COMMITTER_DATE" => "2026-09-30T12:00:00+0000", "GIT_CONFIG_GLOBAL" => "/dev/null", "GIT_CONFIG_SYSTEM" => "/dev/null"}

-> digest_of(a)
  Digest.sha256(Metaflip:Gf2:Scheme.from_terms(a.n, a.m, a.p, a.terms.sort).blob)

-> outcome_of(replayer, path)
  outcome = nil
  begin
    a = replayer.materialize_file(path)
    deps = replayer.deps_file[path]
    ordered = Textx.sorted(deps.keys)
    outcome = "ok " + a.n.to_s + "x" + a.m.to_s + "x" + a.p.to_s + " r" + a.rank.to_s + " " + digest_of(a) + " " + Jsonx.dumps(ordered.map(-> (key) deps[key]))
  rescue e: ReplayError
    outcome = "error " + e.message
  rescue e: FetchError
    outcome = "fetch " + e.message
  outcome

Fsx.with_tempdir(prefix: "gf2-catalogue-") -> (tmp)
  repo = tmp + "/repo"
  Procx.check_output(["cp", "-R", fixtures + "/tree", repo])
  Procx.check_output(["git", "-C", repo, "init", "-q"], env: git_env)
  Procx.check_output(["git", "-C", repo, "add", "-f", "."], env: git_env)
  Procx.check_output(["git", "-C", repo, "commit", "-q", "-m", "fixture"], env: git_env)
  source = MmcSource.new(repo, "HEAD", tmp + "/cache")
  checks += 1
  failures += expect("revision", source.revision, read_file(golden + "/revision.txt").strip)

  lines_of(read_file(golden + "/files.tsv")).each -> (line)
    at = line.index("\t")
    path = line.slice(0, at)
    want = line.slice(at + 1, line.size - at - 1)
    checks += 1
    failures += expect(path + " (no disk cache)", outcome_of(MmcReplayer.new(source, use_disk_cache: false), path), want)
    checks += 1
    failures += expect(path + " (disk cache)", outcome_of(MmcReplayer.new(source), path), want)
    # a second replayer finds what the first one cached, and returns the same
    checks += 1
    failures += expect(path + " (cache hit)", outcome_of(MmcReplayer.new(source), path), want)

  # candidates, best_rank and best
  lines_of(read_file(golden + "/best.tsv")).each -> (line)
    fields = line.split("\t")
    replayer = MmcReplayer.new(source, use_disk_cache: false)
    if fields[0].starts_with?("oriented ")
      shape = fields[0].slice(9, fields[0].size - 9).split("x").map(-> (d) d.to_i)
      a = replayer.best(shape)
      got = "(" + a.n.to_s + ", " + a.m.to_s + ", " + a.p.to_s + ") r" + a.rank.to_s + " " + digest_of(a)
      checks += 1
      failures += expect(fields[0], got, fields[1])
    else
      key = fields[0]
      shape = key.split("x").map(-> (d) d.to_i)
      candidates = replayer.candidates(key).map(-> (e) e["rank"].to_s + ":" + e["file"])
      checks += 1
      failures += expect("candidates " + key, Jsonx.dumps(candidates), fields[1])
      checks += 1
      failures += expect("best_rank " + key, replayer.best_rank(shape).to_s, fields[2])
      a = replayer.best(shape)
      got = a == nil ? "None rNone " : "(" + a.n.to_s + ", " + a.m.to_s + ", " + a.p.to_s + ") r" + a.rank.to_s + " " + digest_of(a)
      checks += 1
      failures += expect("best " + key, got, fields[3])

# ---- the recipes of release bundle A, when the campaign's work directory is there --------------------------------------

work = env("GF2_RECORD_HUNT_WORK")
if work != nil && work != ""
  manifest_path = work + "/release-0929/gf2-searched-records/manifest.json"
  clone = work + "/upstream/mmc"
  cache = work + "/mmc-port/cache"
  if File.exists?(manifest_path) && File.directory?(clone) && File.directory?(cache)
    source = nil
    agree = 0
    total = 0
    Jsonx.load(manifest_path)["rows"].each -> (row)
      details = row["details"]
      if row["kind"] == "recipe-replay" && (!details.key?("rederivable") || details["rederivable"])
        source = MmcSource.new(clone, details["revision"], cache) if source == nil
        total += 1
        outcome = outcome_of(MmcReplayer.new(source, use_disk_cache: false), details["file"])
        agree += 1 if outcome.split(" ")[3] == row["sha256"]
    checks += 1
    failures += expect("replayed catalogue recipes of bundle A that give their row's SHA-256", agree.to_s + " of " + total.to_s, total.to_s + " of " + total.to_s)
    << "bundle A: " + agree.to_s + " of " + total.to_s + " catalogue recipes replayed identically"

if failures > 0
  << "FAIL " + failures.to_s + " of " + checks.to_s + " catalogue checks"
  exit(1)
<< "PASS gf2 catalogue: " + checks.to_s + " checks"
