# The cascade drivers (lib/metaflip/gf2/cascade.w) against the Python originals they port (tools/campaign/next_parents.py,
# project_screen.py, pick_children.py, sweep.py, iterate.py): the ten steps of spec/fixtures/gf2_cascade/cases.json on six seeds of the
# repository, in order, in one scratch directory: two selections of parents (the default kinds, and tie and above with two logs), the
# projection screen of four parents and again (nothing left), the selection of children at three tolerances, a walk screen with two
# repeats and again, and an iterative deepening of three shapes. The walks use a stand-in walker that answers with what the compiled
# walker answered (spec/fixtures/gf2_cascade/in/alt), so no compiled walker is needed. Every step's printed lines (sorted for the
# deepening, whose shapes finish in no fixed order), output (the log of the deepening grouped by shape) and the name and SHA-256 of
# every file it wrote must be the original's, with the scratch directory written `$T`. Prints FAIL lines and exits 1 on a mismatch.
use core/system
use ../lib/metaflip/gf2/cascade
use ../lib/metaflip/gf2/jsonx
use ../lib/metaflip/gf2/procx
use ../lib/metaflip/gf2/fsx
use ../lib/metaflip/gf2/textx

failures = 0 ## i64
checks = 0 ## i64

fixtures = __DIR__ + "/fixtures/gf2_cascade"

-> expect(label, got, want)
  if got != want
    << "FAIL " + label + ": got " + got.to_s.slice(0, 500) + " want " + want.to_s.slice(0, 500)
    return 1
  0

-> expand(text, tmp)
  text.replace("{t}", tmp).replace("{in}", fixtures + "/in")

# The log of a deepening grouped by shape (shapes in order, rows of a shape in the order they were written), one `shape<TAB>row` per line.
-> grouped(text)
  groups = {}
  Textx.splitlines(text).each -> (line)
    shape = Jsonx.loads(line)["shape"]
    groups[shape] = [] if !groups.key?(shape)
    groups[shape].push(line)
  Textx.sorted(groups.keys).map(-> (shape) groups[shape].map(-> (line) shape + "\t" + line + "\n").join("")).join("")

Fsx.with_tempdir(prefix: "gf2-cascade-") -> (tmp)
  Procx.check_output(["cp", "-R", fixtures + "/in/witnesses", tmp + "/witnesses"])
  ["board.json", "proj-a.jsonl", "proj-b.jsonl", "screen_seeds.json", "sweep_seeds.json", "iter_seeds.json"].each -> (name)
    write_file(tmp + "/" + name, read_file(fixtures + "/in/" + name).replace("$WITNESS", tmp + "/witnesses"))
  write_file(tmp + "/board_pick.json", read_file(fixtures + "/in/board_pick.json"))
  write_file(tmp + "/filter.txt", read_file(fixtures + "/in/filter.txt"))
  Fsx.mkdir(tmp + "/sw")
  Fsx.mkdir(tmp + "/it")
  walker = tmp + "/walker-alt.sh"
  write_file(walker, read_file(fixtures + "/in/walker-alt.sh").replace("$ALT", fixtures + "/in/alt"))
  Procx.check_output(["chmod", "755", walker])
  tables = {"lille" => fixtures + "/in/lille.json", "catalog" => nil, "fmm_repo" => nil, "fmm_revision" => "HEAD", "extra_repo" => []}

  Jsonx.load(fixtures + "/cases.json").each -> (step)
    name = step["name"]
    command = step["command"]
    lines = []
    output = nil
    written = nil
    if command == "parents"
      logs = step["logs"].map(-> (log) expand(log, tmp))
      kinds = step.key?("kinds") ? step["kinds"].split(",") : ["below_all", "gf2_valid_only"]
      output = expand(step["out"], tmp)
      lines.push(Cascade.next_parents(expand(step["board"], tmp), output, logs, kinds))
    elsif command == "screen"
      options = {"lille" => tables["lille"], "catalog" => nil, "fmm_repo" => nil, "fmm_revision" => "HEAD", "extra_repo" => [], "mfw_dir" => expand(step["mfw_dir"], tmp), "worker" => nil, "jobs" => 1, "lines" => lines}
      output = expand(step["out"], tmp)
      written = options["mfw_dir"]
      Cascade.project_screen(expand(step["seeds"], tmp), output, options)
    elsif command == "pick"
      output = expand(step["out"], tmp)
      lines.push(Cascade.pick_children(expand(step["proj"], tmp), expand(step["board"], tmp), output, step["tolerance"], tables))
    elsif command == "sweep"
      output = expand(step["out"], tmp)
      written = Fsx.dirname(output) + "/" + Fsx.stem(output) + "_mfw"
      Cascade.sweep(expand(step["seeds"], tmp), output, {"walker" => expand(step["walker"], tmp), "steps" => step["steps"], "jobs" => step["jobs"], "nonce_base" => step["nonce_base"], "filter" => expand(step["filter"], tmp), "repeats" => step["repeats"], "lines" => lines})
    else
      output = expand(step["log"], tmp)
      written = Fsx.dirname(output) + "/" + Fsx.stem(output) + "_mfw"
      Cascade.iterate(expand(step["seeds"], tmp), output, {"walker" => expand(step["walker"], tmp), "steps" => step["steps"], "walks_per_round" => step["walks_per_round"], "patience" => step["patience"], "jobs" => step["jobs"], "nonce_base" => step["nonce_base"], "lines" => lines})
    want = fixtures + "/expected/" + name
    shown = command == "iterate" ? Textx.sorted(lines) : lines
    checks += 1
    failures += expect(name + " output", shown.map(-> (line) line + "\n").join("").replace(tmp, "$T"), read_file(want + "/stdout.txt"))
    text = read_file(output).replace(tmp, "$T")
    text = grouped(text) if command == "iterate"
    checks += 1
    failures += expect(name + " file", text, read_file(want + "/out.txt"))
    files = ""
    files = Fsx.entries(written).map(-> (file) file + " " + Digest.sha256(read_file(written + "/" + file)) + "\n").join("") if written != nil
    checks += 1
    failures += expect(name + " files", files, read_file(want + "/files.txt"))

  # The screen with a process of its own for every parent (what the tool does): the same log, as the processes finish one after the other,
  # and the same files.
  tungsten = env("TUNGSTEN")
  tungsten = file_expand_path(__DIR__ + "/../../../bin/tungsten") if tungsten == nil || tungsten == ""
  tool = file_expand_path(__DIR__ + "/../tools/cascade.w")
  isolated = {"lille" => tables["lille"], "catalog" => nil, "fmm_repo" => nil, "fmm_revision" => "HEAD", "extra_repo" => [], "mfw_dir" => tmp + "/proj_mfw_isolated", "worker" => [tungsten, "run", tool, "--", "screen-one"], "jobs" => 1, "lines" => []}
  Cascade.project_screen(tmp + "/screen_seeds.json", tmp + "/proj_isolated.jsonl", isolated)
  checks += 1
  failures += expect("isolated screen log", read_file(tmp + "/proj_isolated.jsonl").replace(tmp + "/proj_mfw_isolated", "$M").replace(tmp, "$T"), read_file(tmp + "/proj.jsonl").replace(tmp + "/proj_mfw", "$M").replace(tmp, "$T"))
  names = Fsx.entries(tmp + "/proj_mfw")
  checks += 1
  failures += expect("isolated screen files", Fsx.entries(tmp + "/proj_mfw_isolated"), names)
  checks += 1
  failures += expect("isolated screen output", isolated["lines"].join("\n"), "4 parents")

if failures > 0
  << "FAIL " + failures.to_s + " of " + checks.to_s + " cascade checks"
  exit(1)
<< "PASS gf2 cascade: " + checks.to_s + " checks"
