# Content-addressed freshness for runtime-built worker executables.
#
# Workers are compiled into a shared scratch location (/tmp/metaflip_*) and
# were previously considered fresh when the executable's mtime was newer than
# each source input.  Every new checkout, worktree, or `git checkout` gives
# unchanged sources a newer mtime, so a cold lap recompiled ~40 workers
# (30-60 s each) although nothing had changed.  A sidecar `<binary>.inputs`
# now records a SHA-256 over the compiler identity and the exact contents of
# the inputs; the executable is fresh while that digest matches.  A binary
# with no sidecar that still satisfies the old mtime rule (it was built from
# these sources in this tree) is adopted once by writing the sidecar, so
# nothing is rebuilt merely to migrate.
use core/system
use core/file
use core/crypto/sha256
use metallib_cache

-> ffmk_sidecar(binary) (String)
  binary + ".inputs"

# The compiler that produced the executable, by path, size and mtime: the
# launcher plus its sibling `tungsten-compiler` when present.  A rebuilt
# compiler therefore invalidates every worker without hashing its binary.
-> ffmk_compiler_tag(root) (String)
  launcher = ffmc_tungsten(root)
  tag = "compiler:" + launcher
  paths = [launcher]
  slash = launcher.rindex("/") ## i64
  if slash != nil && slash >= 0
    paths.push(launcher.slice(0, slash) + "/tungsten-compiler")
  i = 0 ## i64
  while i < paths.size()
    size = file_size(paths[i])
    mtime = file_mtime_ns(paths[i])
    if size != nil && mtime != nil
      tag = tag + "|" + size.to_s() + ":" + mtime.to_s()
    i += 1
  tag

# Digest of the compiler tag and every input's contents, in order; "" when
# an input is missing.  Paths are deliberately excluded so the same sources
# in another checkout hash identically.
-> ffmk_digest(root, inputs) (String Array)
  body = "metaflip-worker-inputs-v2\n" + ffmk_compiler_tag(root) + "\n"
  i = 0 ## i64
  while i < inputs.size()
    content = read_file(inputs[i])
    if content == nil
      return ""
    body = body + content.size().to_s() + "\n" + content + "\n"
    i += 1
  Crypto:SHA256.hexdigest(body)

-> ffmk_executable(binary) (String) i64
  if system("test -x " + ffmc_shell_quote(binary))
    return 1
  0

# The pre-sidecar rule: the executable is newer than every input.
-> ffmk_mtime_fresh(binary, inputs) (String Array) i64
  binary_mtime = file_mtime_ns(binary)
  if binary_mtime == nil
    return 0
  i = 0 ## i64
  while i < inputs.size()
    source_mtime = file_mtime_ns(inputs[i])
    if source_mtime == nil || binary_mtime < source_mtime
      return 0
    i += 1
  1

-> ffmk_record(root, binary, inputs) (String String Array) i64
  digest = ffmk_digest(root, inputs)
  if digest == "" || ffmk_executable(binary) == 0
    return 0
  ffmk_stamp(binary, digest)

-> ffmk_stamp(binary, digest) (String String) i64
  path = ffmk_sidecar(binary)
  tmp = file_temp_for(path)
  if tmp == nil
    return 0
  ok = write_file(tmp, digest + "\n")
  if ok
    ok = file_rename(tmp, path)
  if !ok
    z = file_unlink(tmp)
    return 0
  1

# Invalidate even failed/partial builds. A present invalid stamp cannot use
# timestamp adoption. Refuse certification if inputs change during the build.
-> ffmk_build(root, binary, inputs, command, metal) (String String Array String i64) i64
  digest = ffmk_digest(root, inputs)
  if digest == "" || command == "" || ffmk_stamp(binary, "building") != 1
    return 0
  if !system(command) || ffmk_executable(binary) == 0
    return 0
  if metal != 0 && ffmc_build_or_source(root, ffmc_generated_source_path(binary), binary) != 1
    return 0
  if ffmk_digest(root, inputs) != digest
    return 0
  ffmk_stamp(binary, digest)

# 1 when `binary` was built from exactly these inputs by this compiler.
-> ffmk_fresh(root, binary, inputs) (String String Array) i64
  if ffmk_executable(binary) == 0
    return 0
  digest = ffmk_digest(root, inputs)
  if digest == ""
    return 0
  recorded = read_file(ffmk_sidecar(binary))
  if recorded != nil && recorded.strip() == digest
    return 1
  if recorded == nil && ffmk_mtime_fresh(binary, inputs) == 1
    return ffmk_record(root, binary, inputs)
  0
