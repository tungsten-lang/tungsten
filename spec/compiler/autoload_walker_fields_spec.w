# spec: compiled
# Autoload must reach class references in EVERY syntactic position.
#
# `collect_autoload_refs` (compiler/lib/loader.w) used to walk the AST by
# probing a hand-kept list of field names, and every position missing from
# that list was a coverage hole:
#
#   * rescue_body / ensure_body   (fixed earlier)
#   * :string_interp parts        — pieces are [tag, payload] pairs in
#                                   Node#parts, not AST children
#   * a trailing block            — hangs off Node#block, which nothing probed
#   * elsif arms, hash-literal values, case subjects, case/when arms, unary
#     operands — elsif arms and hash entries are pairs nested inside a child
#     list; the rest were schema fields the list never named
#
# It now recurses into every schema child, nested lists included. Each hole
# was SILENT: an unresolved class constant produces no compile error, it is
# simply nil, and the program dies later with "undefined method 'x' for nil".
# Every class below is named in exactly ONE position, and none of them loads
# another as a dependency — hoisting any of them to a bare statement, or
# naming a class that pulls one in, would defeat the regression.
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

# --- elsif arm: a [condition, body] pair inside If#elsif_clauses -------------
mean = 0
if items.size() == 0
  mean = -1
elsif items.size() == 1
  mean = Stats.mean([2, 4]).to_i
check("elsif.autoload.stats", mean == 3)

# --- hash-literal value: a [key, value] pair inside HashLiteral#entries ------
palette = {"red": Color.hue_components(0)}
check("hash_value.autoload.color", palette["red"][0] == 255)

# --- case subject and case/when arm ------------------------------------------
fields = 0
case CSV.parse("a,b")[0].size
when 2
  fields = 2
check("case_subject.autoload.csv", fields == 2)

fallback = ""
case fields
when 2
  fallback = Env.get("TUNGSTEN_AUTOLOAD_WALKER_UNSET_VAR", "fallback")
check("case_when_arm.autoload.env", fallback == "fallback")

# Condition-only `case` (no subject): the arm body lives in a :when node.
ones = 0
case
when fields == 2
  ones = BitOps.count_ones_u64(7)
check("case_condition_arm.autoload.bitops", ones == 3)

# --- unary operand -----------------------------------------------------------
check("unary_operand.autoload.dir", !Dir.pwd.empty?)
