# languages/javascript/ast_cache — parsed ASTs in the shared build store.
#
# A parsed program is cached by the SHA-256 of its source bytes (plus the
# AST format version and script/module goal), so a library seen once is never
# parsed again by any checkout or program on this machine:
#
#   <store>/js-ast/<first 2 hex>/<sha256>-v<JS_AST_VERSION>-<s|m>.jsast
#
# <store> is the build store every Tungsten checkout shares:
# TUNGSTEN_BUILD_STORE, else TUNGSTEN_HOME/build, else ~/.tungsten/build.
# Entries are published with a temp file and a rename, and a reader renews an
# entry's mtime when it loads it, so bin/commands/cache_gc.sh only sweeps entries
# nothing has used for a week.
#
#   r = js_parse_cached(src, false)   # [program, :hit / :miss]

use ast_codec

-> js_store_dir
  d = Env.get("TUNGSTEN_BUILD_STORE")
  return d if d != nil && d.size > 0
  d = Env.get("TUNGSTEN_HOME")
  return d + "/build" if d != nil && d.size > 0
  home = Env.get("HOME")
  home = "" if home == nil
  home + "/.tungsten/build"

-> js_ast_cache_key(src, mod)
  Digest.sha256(src) + "-v" + JS_AST_VERSION.to_s + (mod ? "-m" : "-s")

-> js_ast_cache_path(key)
  js_store_dir() + "/js-ast/" + key.slice(0, 2) + "/" + key + ".jsast"

# Loads the cached program for src, or nil.
-> js_ast_cache_load(src, mod)
  path = js_ast_cache_path(js_ast_cache_key(src, mod))
  return nil if !File.exist?(path)
  img = File.read(path)
  prog = js_ast_decode(img)
  # renew the entry so the store's sweep sees it as in use
  File.touch(path) if prog != nil
  prog

-> js_ast_cache_store(src, mod, prog)
  path = js_ast_cache_path(js_ast_cache_key(src, mod))
  dir = path.slice(0, path.rindex("/"))
  Dir.mkdir_p(dir) if !Dir.exist?(dir)
  img = js_ast_encode(prog, mod)[0]
  tmp = path + ".tmp-" + clock_ms().to_s + "-" + UUID.v4.to_s
  File.write(tmp, img)
  File.rename(tmp, path)
  path

# Parse through the cache: [program, :hit] or [program, :miss]. A syntax
# error raises as JsParser does (failures are not cached).
-> js_parse_cached(src, mod)
  prog = js_ast_cache_load(src, mod)
  return [prog, :hit] if prog != nil
  p = JsParser.new(src, mod)
  prog = p.parse_program()
  js_ast_cache_store(src, mod, prog)
  [prog, :miss]
