# Classification guard for metaflip's unit tests, mirroring the root gate's
# fail-closed discovery: every tracked spec/*_test.w must appear in exactly one
# of spec/interpreted_tests.txt (run by the metaflip_unit_shard<N> suites) or
# spec/native_tests.txt (with a reason), so a newly added test cannot silently
# stay outside CI.
use metaflip_unit_harness

problems = []
tests = []
capture("cd '" + __DIR__ + "' && ls *_test.w").split("\n").each -> (name)
  tests.push("spec/" + name) if name.size > 0
if tests.size == 0
  problems.push("no spec/*_test.w files found next to " + __DIR__)

interpreted = {}
mfu_manifest_rows("interpreted_tests.txt").each -> (row)
  if row.size != 2 || row[0].to_i < 1
    problems.push("malformed interpreted_tests.txt row (expected `<shard> spec/<name>_test.w`): " + row.join(" "))
  else
    problems.push("listed twice in interpreted_tests.txt: " + row[1]) if interpreted.key?(row[1])
    interpreted[row[1]] = row[0].to_i

reasons = ["native", "argv", "gpu", "timeout"]
native = {}
mfu_manifest_rows("native_tests.txt").each -> (row)
  if row.size != 2 || !reasons.include?(row[1])
    problems.push("malformed native_tests.txt row (expected `spec/<name>_test.w <" + reasons.join("|") + ">`): " + row.join(" "))
  else
    problems.push("listed twice in native_tests.txt: " + row[0]) if native.key?(row[0])
    native[row[0]] = row[1]

tests.each -> (path)
  listed_interpreted = interpreted.key?(path)
  listed_native = native.key?(path)
  if !listed_interpreted && !listed_native
    problems.push("unclassified test; add it to spec/interpreted_tests.txt or spec/native_tests.txt: " + path)
  if listed_interpreted && listed_native
    problems.push("listed in both manifests: " + path)

interpreted.keys.each -> (path)
  problems.push("interpreted_tests.txt lists a missing file: " + path) if !tests.include?(path)
  shard = interpreted[path]
  runner = "metaflip_unit_shard" + shard.to_s + "_spec.w"
  problems.push("no runner spec/" + runner + " for shard [shard]: " + path) if !File.exist?(__DIR__ + "/" + runner)

native.keys.each -> (path)
  problems.push("native_tests.txt lists a missing file: " + path) if !tests.include?(path)

shard = 1
while File.exist?(__DIR__ + "/metaflip_unit_shard" + shard.to_s + "_spec.w")
  problems.push("spec/metaflip_unit_shard[shard]_spec.w has no tests in interpreted_tests.txt") if mfu_shard_tests(shard).size == 0
  shard += 1
shards = shard - 1

if problems.size > 0
  problems.each -> (problem)
    << "  " + problem
  << "FAIL metaflip test manifests: [problems.size] problems"
  exit(1)
<< "PASS metaflip test manifests: [tests.size] tests, [interpreted.size] interpreted across [shards] shards, [native.size] native-only"
