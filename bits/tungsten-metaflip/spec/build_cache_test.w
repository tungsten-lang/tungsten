# Content-addressed worker freshness (kernels/build_cache.w): an executable
# stays fresh across mtime-only changes to its inputs (a new checkout or
# worktree), goes stale when an input's content changes, and a pre-sidecar
# binary that satisfies the old mtime rule is adopted without a rebuild.
use core/system
use ../lib/metaflip/kernels/build_cache

failures = 0 ## i64

-> cache_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL " + label
    return 1
  0

-> cache_write_exec(path, body) (String String) i64
  z = write_file(path, body)
  if system("chmod +x " + ffmc_shell_quote(path))
    return 1
  0

root = __DIR__ + "/../lib/metaflip"
tmp = env("TMPDIR")
if tmp == nil || tmp == ""
  tmp = "/tmp"
scratch = capture("mktemp -d " + ffmc_shell_quote(tmp + "/metaflip-build-cache-XXXXXX")).strip()
if scratch == ""
  << "FAIL cannot create scratch directory"
  exit(1)
a = scratch + "/a.w"
b = scratch + "/b.w"
binary = scratch + "/worker"
z = write_file(a, "alpha\n")
z = write_file(b, "beta\n")
z = system("sleep 0.05")
# 1. Executable newer than its inputs, no sidecar: adopted, sidecar written.
z = cache_write_exec(binary, "#!/bin/sh\nexit 0\n")
failures += cache_expect("fresh binary without sidecar is adopted", ffmk_fresh(root, binary, [a, b]) == 1)
failures += cache_expect("adoption records the sidecar", read_file(ffmk_sidecar(binary)) != nil)
# 2. mtime-only change (a fresh checkout): still fresh.
z = system("sleep 0.05")
z = system("touch " + ffmc_shell_quote(a) + " " + ffmc_shell_quote(b))
failures += cache_expect("touched inputs with identical content stay fresh", ffmk_fresh(root, binary, [a, b]) == 1)
failures += cache_expect("old mtime rule alone would have rebuilt", ffmk_mtime_fresh(binary, [a, b]) == 0)
# 3. Content change: stale.
z = write_file(b, "beta prime\n")
failures += cache_expect("changed input content is stale", ffmk_fresh(root, binary, [a, b]) == 0)
# 4. Rebuild (binary rewritten newer): adopted again with the new digest.
z = system("sleep 0.05")
z = cache_write_exec(binary, "#!/bin/sh\nexit 0\n")
failures += cache_expect("rebuilt binary is fresh", ffmk_fresh(root, binary, [a, b]) == 1)
failures += cache_expect("sidecar carries the new digest", read_file(ffmk_sidecar(binary)).strip() == ffmk_digest(root, [a, b]))
# 5. Missing input or executable: never fresh.
failures += cache_expect("missing input is stale", ffmk_fresh(root, binary, [a, scratch + "/absent.w"]) == 0)
z = system("rm -f " + ffmc_shell_quote(binary))
failures += cache_expect("missing executable is stale", ffmk_fresh(root, binary, [a, b]) == 0)
z = system("rm -rf " + ffmc_shell_quote(scratch))

if failures > 0
  << "metaflip build cache: " + failures.to_s() + " failure(s)"
  exit(1)
<< "metaflip build cache: ok"
