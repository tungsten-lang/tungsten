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
  files = ffmf_listing(root, "find lib/metaflip -type f | LC_ALL=C sort")
  out = ""
  i = 0 ## i64
  while i < files.size()
    rel = files[i]
    if rel != "lib/metaflip/SHA256SUMS"
      out = out + ffmf_hash_file(root, rel) + "  " + rel + "\n"
    i += 1
  out

-> ffmf_render_runtime_sources(root) (String)
  files = ffmf_listing(root, "(echo bin/metaflip.w; echo lib/metaflip.w; find lib/metaflip -type f -name '*.w' | LC_ALL=C sort)")
  out = "source_path\tsha256\n"
  i = 0 ## i64
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
