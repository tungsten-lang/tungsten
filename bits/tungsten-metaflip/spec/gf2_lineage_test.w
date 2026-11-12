# The lineage verifier (lib/metaflip/gf2/lineage.w) against the Python original (tools/verify_gf2_lineage.py): the rank arithmetic
# of recipes, a good bundle with every derived row kind (closure, basis, walk, projection with and without a basis rewrite),
# seed rows of every kind with and without a source (retained, archived, public-mod2, recipe-replay), walk replays through
# stand-in walkers, and tampered bundles, which must all be rejected. The goldens in spec/fixtures/gf2_lineage/expected are
# what the original prints (generate.py runs it, and checks that it accepts and rejects the same cases); the trees behind the
# `archived` and `public-mod2` rows are committed here with fixed author and date, so the revisions in the manifests hold.
# Prints FAIL lines and exits 1 on a mismatch.
use core/system
use ../lib/metaflip/gf2/lineage
use ../lib/metaflip/gf2/jsonx
use ../lib/metaflip/gf2/procx
use ../lib/metaflip/gf2/fsx

failures = 0 ## i64
checks = 0 ## i64

fixtures = __DIR__ + "/fixtures/gf2_lineage"

-> expect(label, got, want)
  if got != want
    << "FAIL " + label + ": got " + got.to_s.slice(0, 300) + " want " + want.to_s.slice(0, 300)
    return 1
  0

# ---- the rank arithmetic of recipes ---------------------------------------------------------------

seven = {"kind" => "seed", "rank" => 7, "shape" => [2, 2, 2], "source" => "lib/metaflip/seeds/gf2/strassen.txt"}
naive = {"kind" => "naive", "shape" => [2, 2, 3]}
checks += 1
failures += expect("split rank", Metaflip:Gf2:Lineage.recipe_rank({"kind" => "split", "rank" => 19, "axis" => 2, "left" => seven, "right" => naive}), 19)
checks += 1
failures += expect("product rank", Metaflip:Gf2:Lineage.recipe_rank({"kind" => "product", "rank" => 49, "left" => seven, "right" => seven}), 49)
checks += 1
failures += expect("projection rank", Metaflip:Gf2:Lineage.recipe_rank({"kind" => "projection", "rank" => 5, "parent" => seven}), 5)
[{"kind" => "split", "rank" => 20, "axis" => 2, "left" => seven, "right" => naive},
 {"kind" => "product", "rank" => 48, "left" => seven, "right" => seven},
 {"kind" => "magic", "rank" => 7, "left" => seven, "right" => seven}].each -> (broken)
  refused = false
  begin
    Metaflip:Gf2:Lineage.recipe_rank(broken)
  rescue e: LineageError
    refused = true
  checks += 1
  failures += expect("inconsistent recipe " + broken["kind"] + " " + broken["rank"].to_s, refused, true)

# ---- the bundles ----------------------------------------------------------------------------------

git_env = {"GIT_AUTHOR_NAME" => "fixture", "GIT_AUTHOR_EMAIL" => "fixture@example.invalid", "GIT_COMMITTER_NAME" => "fixture", "GIT_COMMITTER_EMAIL" => "fixture@example.invalid", "GIT_AUTHOR_DATE" => "2026-09-30T12:00:00+0000", "GIT_COMMITTER_DATE" => "2026-09-30T12:00:00+0000", "GIT_CONFIG_GLOBAL" => "/dev/null", "GIT_CONFIG_SYSTEM" => "/dev/null"}

-> committed(tree, target, env)
  Procx.check_output(["cp", "-R", tree, target])
  Procx.check_output(["git", "-C", target, "init", "-q"], env: env)
  Procx.check_output(["git", "-C", target, "add", "-f", "."], env: env)
  Procx.check_output(["git", "-C", target, "commit", "-q", "-m", "fixture"], env: env)
  target

cases = Jsonx.load(fixtures + "/cases.json")
Fsx.with_tempdir(prefix: "gf2-lineage-") -> (tmp)
  history = committed(fixtures + "/in/history", tmp + "/history", git_env)
  schemes = committed(fixtures + "/in/schemes", tmp + "/schemes", git_env)
  walkers = {}
  ["copy", "corrupt", "fail"].each -> (name)
    path = tmp + "/walker-" + name + ".sh"
    write_file(path, read_file(fixtures + "/in/walker-" + name + ".sh"))
    Procx.check_output(["chmod", "755", path])
    walkers["$WALKER_" + name.upcase] = path
  catalogue = committed(fixtures + "/../gf2_catalogue/tree", tmp + "/catalogue", git_env)
  places = {"$REPO" => fixtures + "/in/repo", "$HISTORY" => history, "$SCHEMES" => schemes, "$CATALOGUE" => catalogue, "$CACHE" => tmp + "/mmc-cache"}
  walkers.each -> (key, path)
    places[key] = path

  cases.each -> (entry)
    options = {"sources" => {}}
    given = entry["options"]
    if given.key?("sources")
      given["sources"].each -> (name, place)
        options["sources"][name] = places[place]
    options["repo_root"] = places[given["repo_root"]] if given.key?("repo_root")
    options["replay_walk"] = places[given["replay_walk"]] if given.key?("replay_walk")
    options["replay_max_rank"] = given["replay_max_rank"] if given.key?("replay_max_rank")
    options["cache_dir"] = places[given["cache_dir"]] if given.key?("cache_dir")
    result = nil
    outcome = "ok"
    begin
      result = Metaflip:Gf2:Lineage.verify(fixtures + "/in/bundles/" + entry["bundle"], options)
    rescue e: LineageError
      outcome = "rejected"
    checks += 1
    failures += expect(entry["name"] + " outcome", outcome, entry["expect"])
    if outcome == "ok" && entry["expect"] == "ok"
      text = Metaflip:Gf2:Lineage.lines(result).join("\n") + "\n"
      checks += 1
      failures += expect(entry["name"] + " output", text.replace("(Tungsten, two gates)", "(Python)"), read_file(fixtures + "/expected/" + entry["name"] + ".txt"))

if failures > 0
  << "FAIL " + failures.to_s + " of " + checks.to_s + " lineage checks"
  exit(1)
<< "PASS gf2 lineage: " + checks.to_s + " checks"
