# Autoload must reach class references in EVERY syntactic position.
#
# `collect_autoload_refs` (compiler/lib/loader.w) walks the AST by probing a
# fixed list of field names, and it has had three separate coverage holes:
#
#   * rescue_body / ensure_body   (fixed earlier)
#   * :string_interp parts        — pieces are [tag, payload] pairs in
#                                   Node#parts, not AST children
#   * a trailing block            — hangs off Node#block, which nothing probed
#
# Each hole is SILENT: an unresolved class constant produces no compile error,
# it is simply nil, and the program dies later with "undefined method 'x' for
# nil". Every class below is named in exactly ONE position — hoisting any of
# them to a bare statement would defeat the regression.
#
# Run: `bin/tungsten -o /tmp/awf spec/compiler/autoload_walker_fields_spec.w && /tmp/awf`

-> check(name, ok)
  if ok
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

# --- string interpolation parts ---------------------------------------------
cpus = "[System.cpu_count]"
check("interp.autoload.system", cpus.size() > 0 && cpus != "")

gate = "[Sandbox.active?]"
check("interp.autoload.sandbox", gate == "false" || gate == "true")

# Past a literal part, inside a larger interpolated string.
msg = "cpus=[System.cpu_count] gate=[Sandbox.active?]"
check("interp.autoload.multipart", msg.include?("cpus=") && msg.include?("gate="))

# --- trailing block bodies ---------------------------------------------------
# JSON appears ONLY inside these blocks. Before the fix this raised
# "undefined method 'JSON' for <enclosing class>": the constant was never
# registered, so it lowered to a self-method call.
encoded = []
items = ["x"]
items.each -> (item)
  encoded.push(JSON.encode({k: item}))
check("block.autoload.json", encoded.size() == 1)
check("block.autoload.json_shape", encoded[0].include?("k"))

# A block on a different receiver shape (map, not each), still block-only.
mapped = ["a"].map -> (item)
  JSON.encode({v: item})
check("block.autoload.json_map", mapped.size() == 1)
check("block.autoload.json_map_shape", mapped[0].include?("v"))

# --- a class named only inside a block AND inside an interpolation -----------
nested = []
["1"].each -> (item)
  nested.push("[Base64.encode(item)]")
check("block.interp.autoload.base64", nested.size() == 1)
check("block.interp.autoload.base64_nonempty", nested[0] != "")
