# The projection/basis/walk search (lib/metaflip/gf2/projection_walks.w) against the Python original
# (tools/search_wide_projection_walks.py) on the 3x3x4 rank-29 seed: the listing of the selected children, a depth-2 search with two
# children per parent (six walks), a depth-1 search with one, and the searches that must end badly (a walker that writes garbage, that
# answers with another shape, that fails, an output directory that exists, a nonce out of range, a rank table with two ranks for one
# format). The walks use stand-in walkers that answer with what the compiled walker returned (spec/fixtures/gf2_projection_walks/in/alt),
# so no compiled walker is needed; the goldens (stdout, manifest.json with the scratch directory written `$T`, the name and SHA-256 of
# every file next to it) are what the original produced (generate.py runs it and checks that the stand-ins answer as the real walker
# did). The Ruby verifier (tools/verify_tensor.rb) runs in both. Prints FAIL lines and exits 1 on a mismatch.
use core/system
use ../lib/metaflip/gf2/projection_walks
use ../lib/metaflip/gf2/jsonx
use ../lib/metaflip/gf2/procx
use ../lib/metaflip/gf2/fsx

failures = 0 ## i64
checks = 0 ## i64

fixtures = __DIR__ + "/fixtures/gf2_projection_walks"

-> expect(label, got, want)
  if got != want
    << "FAIL " + label + ": got " + got.to_s.slice(0, 400) + " want " + want.to_s.slice(0, 400)
    return 1
  0

-> expand(text, tmp)
  text.replace("{t}", tmp).replace("{in}", fixtures + "/in")

# The options of the library for the command line of a case, with the defaults of the original's.
-> options_from(args, tmp)
  options = {"depth" => 1, "beam" => 2, "steps" => 100000000, "nonce_base" => 19071, "list_only" => false, "walker" => nil, "output_dir" => nil, "verifier" => __DIR__ + "/../tools/verify_tensor.rb"}
  i = 0 ## i64
  while i < args.size
    flag = args[i]
    if flag == "--list-only"
      options["list_only"] = true
    else
      value = expand(args[i + 1], tmp)
      i += 1
      name = flag.slice(2, flag.size - 2).replace("-", "_")
      if name == "depth" || name == "beam" || name == "steps" || name == "nonce_base"
        options[name] = value.to_i
      else
        options[name] = value
    i += 1
  options

Fsx.with_tempdir(prefix: "gf2-projwalks-") -> (tmp)
  write_file(tmp + "/seed.mfw", read_file(fixtures + "/in/seed.mfw"))
  ["alt", "corrupt", "shape", "fail"].each -> (name)
    path = tmp + "/walker-" + name + ".sh"
    write_file(path, read_file(fixtures + "/in/walker-" + name + ".sh").replace("$ALT", fixtures + "/in/alt").replace("$IN", fixtures + "/in"))
    Procx.check_output(["chmod", "755", path])

  Jsonx.load(fixtures + "/cases.json").each -> (entry)
    name = entry["name"]
    options = options_from(entry["args"], tmp)
    lines = []
    options["lines"] = lines
    outcome = "ok"
    begin
      ProjectionWalks.run(options)
    rescue failure
      outcome = "rejected"
    checks += 1
    failures += expect(name + " outcome", outcome, entry["expect"])
    if outcome == "ok" && entry["expect"] == "ok"
      want = fixtures + "/expected/" + name
      checks += 1
      failures += expect(name + " output", lines.map(-> (line) line + "\n").join("").replace(tmp, "$T"), read_file(want + "/stdout.txt"))
      if !options["list_only"]
        out = options["output_dir"]
        checks += 1
        failures += expect(name + " manifest", read_file(out + "/manifest.json").replace(tmp, "$T"), read_file(want + "/manifest.json"))
        listing = Fsx.entries(out).select(-> (file) file != "manifest.json").map(-> (file) file + " " + Digest.sha256(read_file(out + "/" + file)) + "\n").join("")
        checks += 1
        failures += expect(name + " files", listing, read_file(want + "/files.txt"))

if failures > 0
  << "FAIL " + failures.to_s + " of " + checks.to_s + " projection walk checks"
  exit(1)
<< "PASS gf2 projection walks: " + checks.to_s + " checks"
