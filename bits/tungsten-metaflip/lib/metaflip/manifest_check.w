# Rendering and verification of the packaged runtime manifests.
#
# `lib/metaflip/SHA256SUMS` covers every file of the runtime subtree other
# than itself; `lib/metaflip/manifests/runtime-sources.tsv` records the
# Tungsten source closure (the executable entry plus every `.w` file under
# the subtree).  `tools/regen_manifests.w` rewrites both from this module and
# `spec/runtime_manifests_test.w` fails closed on any stale, missing, or
# extra entry, so the manifests can never silently drift from the tree.
use core/system
use core/crypto/sha256
use paths

-> ffmf_lines(text) (String)
  out = []
  if text == nil
    return out
  parts = text.split("\n")
  i = 0 ## i64
  while i < parts.size()
    if parts[i] != ""
      out.push(parts[i])
    i += 1
  out

-> ffmf_listing(root, command) (String String)
  ffmf_lines(capture("cd " + ffls_shell_quote(root) + " && " + command))

# Generated GPU sidecars and compiler outputs sit beside the sources in a
# working tree that has run the fleet; they are never part of the packaged
# runtime, so neither manifest lists them.
-> ffmf_generated(rel) (String) i64
  suffixes = [".metal", ".cu", ".air", ".metallib", ".ll", ".sidemap", ".wc"]
  i = 0 ## i64
  while i < suffixes.size()
    if rel.ends_with?(suffixes[i])
      return 1
    i += 1
  if rel.include?(".dSYM/")
    return 1
  0

# Files of the runtime subtree: the tracked files inside a git checkout,
# otherwise (an unpacked package) everything on disk except generated
# artifacts.  Both listings are C-sorted so the manifests are reproducible.
-> ffmf_runtime_files(root, only_sources) (String i64)
  tracked = ffmf_listing(root, "git ls-files -- lib/metaflip 2>/dev/null | LC_ALL=C sort")
  if tracked.size() == 0
    tracked = ffmf_listing(root, "find lib/metaflip -type f | LC_ALL=C sort")
  out = []
  i = 0 ## i64
  while i < tracked.size()
    rel = tracked[i]
    keep = 1 ## i64
    if ffmf_generated(rel) == 1 || rel == "lib/metaflip/SHA256SUMS"
      keep = 0
    if only_sources == 1 && !rel.ends_with?(".w")
      keep = 0
    if keep == 1
      out.push(rel)
    i += 1
  out

-> ffmf_hash_file(root, rel) (String String)
  body = read_file(root + "/" + rel)
  if body == nil
    return ""
  Crypto:SHA256.hexdigest(body)

-> ffmf_sha256sums_path(root) (String)
  root + "/lib/metaflip/SHA256SUMS"

-> ffmf_runtime_sources_path(root) (String)
  root + "/lib/metaflip/manifests/runtime-sources.tsv"

-> ffmf_render_sha256sums(root) (String)
  files = ffmf_runtime_files(root, 0)
  out = ""
  i = 0 ## i64
  while i < files.size()
    out = out + ffmf_hash_file(root, files[i]) + "  " + files[i] + "\n"
    i += 1
  out

-> ffmf_render_runtime_sources(root) (String)
  sources = ffmf_runtime_files(root, 1)
  files = ["bin/metaflip.w", "lib/metaflip.w"]
  i = 0 ## i64
  while i < sources.size()
    files.push(sources[i])
    i += 1
  out = "source_path\tsha256\n"
  i = 0
  while i < files.size()
    out = out + files[i] + "\t" + ffmf_hash_file(root, files[i]) + "\n"
    i += 1
  out

# Lines present in `expected` but not `actual` are reported as stale or
# missing; lines only in `actual` as extra.  Order is part of the contract.
-> ffmf_compare(label, expected, actual, problems) (String String String Array) i64
  if actual == nil
    problems.push(label + ": file is missing")
    return 1
  if expected == actual
    return 0
  want = ffmf_lines(expected)
  have = ffmf_lines(actual)
  i = 0 ## i64
  while i < want.size()
    if !have.include?(want[i])
      problems.push(label + ": stale or missing entry: " + want[i])
    i += 1
  i = 0
  while i < have.size()
    if !want.include?(have[i])
      problems.push(label + ": extra entry: " + have[i])
    i += 1
  if problems.size() == 0
    problems.push(label + ": entries are out of order")
  1

-> ffmf_check(root) (String)
  problems = []
  z = ffmf_compare("runtime-sources.tsv", ffmf_render_runtime_sources(root), read_file(ffmf_runtime_sources_path(root)), problems) ## i64
  z = ffmf_compare("SHA256SUMS", ffmf_render_sha256sums(root), read_file(ffmf_sha256sums_path(root)), problems)
  problems

# runtime-sources.tsv is itself covered by SHA256SUMS, so it is written first.
-> ffmf_write(root) (String) i64
  write_file(ffmf_runtime_sources_path(root), ffmf_render_runtime_sources(root))
  write_file(ffmf_sha256sums_path(root), ffmf_render_sha256sums(root))
  1
