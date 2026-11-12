# Recipe replay (lib/metaflip/gf2/recipes.w) against the Python original (tools/wide_composition_recipes.py): every
# recipe kind, other orientations, and recipes with a mutated rank, cut, reference, hash or path, which must be rejected with the
# original's message. The goldens in spec/fixtures/gf2_recipes/expected/cases.tsv come from the original
# (spec/fixtures/gf2_recipes/generate.py runs it). Prints FAIL lines and exits 1 on a mismatch.
use core/system
use ../lib/metaflip/gf2/recipes
use ../lib/metaflip/gf2/jsonx

failures = 0 ## i64
checks = 0 ## i64

fixtures = __DIR__ + "/fixtures/gf2_recipes"
root = Fsx.resolve(__DIR__ + "/../../..")

-> lines_of(terms)
  terms.map(-> (t) Metaflip:Gf2:Bits.to_hex(t[0]) + " " + Metaflip:Gf2:Bits.to_hex(t[1]) + " " + Metaflip:Gf2:Bits.to_hex(t[2]) + "\n").join("")

recipes = Jsonx.load(fixtures + "/in/recipes.json")
# the schemes a caller holds: name => [shape, terms]
states = {}
[["s1", [2, 2, 2]], ["s2", [2, 2, 5]]].each -> (entry)
  terms = Metaflip:Gf2:RecordBoard.decimal_terms(read_file(fixtures + "/in/state_" + entry[0] + ".txt"))
  states[entry[0]] = [entry[1], terms.sort]

leaves = {}
read_file(fixtures + "/expected/cases.tsv").split("\n").select(-> (line) line != "").each -> (line)
  fields = line.split("\t")
  name = fields[0]
  checks += 1
  recipe = recipes[name]
  outcome = nil
  begin
    terms = Metaflip:Gf2:Recipes.replay(recipe, root, states, leaves)
    outcome = "ok\t" + terms.size.to_s + "\t" + Digest.sha256(lines_of(terms))
  rescue failure
    outcome = "error\t" + failure.to_s
  want = fields[1..-1].join("\t")
  if outcome != want
    << "FAIL " + name + ": got " + outcome.slice(0, 90) + " want " + want.slice(0, 90)
    failures += 1

# dependencies: the state hashes a recipe names
checks += 1
failures += 1 if Metaflip:Gf2:Recipes.dependencies(recipes["split-mixed"]).size != 0
checks += 1
failures += 1 if Metaflip:Gf2:Recipes.dependencies(recipes["seed-state"]) != ["s1"]

if failures > 0
  << "FAIL " + failures.to_s + " of " + checks.to_s + " recipe checks"
  exit(1)
<< "PASS gf2 recipes: " + checks.to_s + " checks"
