# The matmulcatalog seed driver (lib/metaflip/gf2/catalogue_seeds.w) against the Python original (tools/mmc_gf2_seeds.py): the ten
# steps of spec/fixtures/gf2_catalogue_seeds/cases.json on a small synthetic catalogue, run in order over one shared cache
# directory: three target selections (slack, minimum dimension), replays of one target list without a scoreboard, again (nothing
# left to do), with a scoreboard (a witness serves as a leaf), allowing integer-only leaves, retrying the failures, restricted to
# some shapes and files, and from the selected targets. For every step the printed lines, the targets file, the results log (with
# `secs` zeroed), the seed list and the name and SHA-256 of every seed file must be what the original produced; the scratch
# directory is written `$T` in all of them. Prints FAIL lines and exits 1 on a mismatch.
use core/system
use ../lib/metaflip/gf2/catalogue_seeds
use ../lib/metaflip/gf2/jsonx
use ../lib/metaflip/gf2/procx
use ../lib/metaflip/gf2/fsx
use ../lib/metaflip/gf2/textx

failures = 0 ## i64
checks = 0 ## i64

fixtures = __DIR__ + "/fixtures/gf2_catalogue_seeds"

-> expect(label, got, want)
  if got != want
    << "FAIL " + label + ": got " + got.to_s.slice(0, 400) + " want " + want.to_s.slice(0, 400)
    return 1
  0

git_env = {"GIT_AUTHOR_NAME" => "fixture", "GIT_AUTHOR_EMAIL" => "fixture@example.invalid", "GIT_COMMITTER_NAME" => "fixture", "GIT_COMMITTER_EMAIL" => "fixture@example.invalid", "GIT_AUTHOR_DATE" => "2026-09-30T12:00:00+0000", "GIT_COMMITTER_DATE" => "2026-09-30T12:00:00+0000", "GIT_CONFIG_GLOBAL" => "/dev/null", "GIT_CONFIG_SYSTEM" => "/dev/null"}

-> committed(tree, target, env)
  Procx.check_output(["cp", "-R", tree, target])
  Procx.check_output(["git", "-C", target, "init", "-q"], env: env)
  Procx.check_output(["git", "-C", target, "add", "-f", "."], env: env)
  Procx.check_output(["git", "-C", target, "commit", "-q", "-m", "fixture"], env: env)
  target

-> expand(text, places)
  expanded = text
  places.each -> (token, value)
    expanded = expanded.replace(token, value)
  expanded

# The options of the library for the command line of a step: [command, options...] as the original's argparse would read it.
-> options_from(args, places)
  options = {"extra_repo" => [], "slack" => 0, "min_dim" => 2, "revision" => "HEAD", "fmm_revision" => "HEAD", "fmm_repo" => nil, "board" => nil, "only" => nil, "allow_nonf2" => false, "retry_failed" => false}
  i = 1 ## i64
  while i < args.size
    flag = args[i]
    if flag == "--allow-nonf2"
      options["allow_nonf2"] = true
    elsif flag == "--retry-failed"
      options["retry_failed"] = true
    elsif flag == "--only"
      options["only"] = []
      while i + 1 < args.size && !args[i + 1].starts_with?("--")
        options["only"].push(expand(args[i + 1], places))
        i += 1
    else
      value = expand(args[i + 1], places)
      i += 1
      name = flag.slice(2, flag.size - 2).replace("-", "_")
      if name == "extra_repo"
        options["extra_repo"].push(value)
      elsif name == "slack" || name == "min_dim"
        options[name] = value.to_i
      else
        options[name] = value
    i += 1
  options

# The results log with `secs` zeroed, one row per line.
-> zeroed(text)
  rows = Textx.splitlines(text).map -> (line)
    row = Jsonx.loads(line)
    row["secs"] = 0
    Jsonx.dumps(row) + "\n"
  rows.join("")

Fsx.with_tempdir(prefix: "gf2-seeds-") -> (tmp)
  repo = committed(fixtures + "/tree", tmp + "/repo", git_env)
  checks += 1
  failures += expect("revision of the tree", Procx.check_output(["git", "-C", repo, "rev-parse", "HEAD"], env: git_env).strip, read_file(fixtures + "/expected/revision.txt").strip)
  Procx.check_output(["cp", "-R", fixtures + "/in/witnesses", tmp + "/witnesses"])
  write_file(tmp + "/board.json", read_file(fixtures + "/in/board.json").replace("$WITNESS", tmp + "/witnesses"))
  places = {"{clone}" => repo, "{cache}" => tmp + "/cache", "{in}" => fixtures + "/in", "{t}" => tmp}

  Jsonx.load(fixtures + "/cases.json").each -> (entry)
    name = entry["name"]
    args = entry["args"]
    options = options_from(args, places)
    lines = []
    if args[0] == "targets"
      lines.push(CatalogueSeeds.select_targets(options))
    else
      options["lines"] = lines
      CatalogueSeeds.replay(options)
    want = fixtures + "/expected/" + name
    checks += 1
    failures += expect(name + " output", lines.map(-> (line) line + "\n").join("").replace(tmp, "$T"), read_file(want + "/stdout.txt"))
    if args[0] == "targets"
      checks += 1
      failures += expect(name + " targets", read_file(options["out"]), read_file(want + "/targets.json"))
    else
      out = options["out"]
      checks += 1
      failures += expect(name + " results", zeroed(read_file(out + "/results.jsonl")).replace(tmp, "$T"), read_file(want + "/results.jsonl"))
      checks += 1
      failures += expect(name + " seeds", read_file(out + "/seeds.json").replace(tmp, "$T"), read_file(want + "/seeds.json"))
      listing = Fsx.glob(out, "*.mfw").map(-> (path) Fsx.basename(path) + " " + Digest.sha256(read_file(path)) + "\n").join("")
      checks += 1
      failures += expect(name + " files", listing, read_file(want + "/files.txt"))

if failures > 0
  << "FAIL " + failures.to_s + " of " + checks.to_s + " catalogue seed checks"
  exit(1)
<< "PASS gf2 catalogue seeds: " + checks.to_s + " checks"
