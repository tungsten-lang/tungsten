# JSON.parse must produce identical values on BOTH engines.
#
# Regression: `JSON.parse` was unusable interpreted — it died with
# "Undefined method 'parse_value_b'". `-> .parse` calls its sibling class
# methods by bare name (`parse_value_b(s, view, n, 0)`), and the interpreter's
# implicit-self lookup returned nil for a class sentinel, so it never found
# them. The compiled engine resolved the same call fine, so this was a silent
# engine-parity hole. Fixed in interpreter.w `implicit_self_method`.
#
# NOTE ON ESCAPING: `[` and `]` inside a Tungsten string literal INTERPOLATE,
# so a JSON array must be written "\[1,2\]". Unescaped, "[1,2,3]" evaluates the
# interpolation and hands JSON the string "1" — the parser never sees an array.
# Do not "simplify" the escapes away; the test silently stops testing arrays.
#
# Run: `bin/tungsten -o /tmp/jp spec/core/json_parse_spec.w && /tmp/jp`
#      `bin/tungsten run spec/core/json_parse_spec.w`   (engine parity)

-> check(name, ok)
  if ok
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

# --- objects -----------------------------------------------------------------
o = JSON.parse("{\"name\":\"hi\",\"n\":42}")
check("obj.string_value", o["name"] == "hi")
check("obj.int_value", o["n"] == 42)

empty_obj = JSON.parse("{}")
check("obj.empty", empty_obj.size() == 0)

# --- arrays ------------------------------------------------------------------
a = JSON.parse("\[1,2,3\]")
check("arr.type", type(a) == "Array")
check("arr.size", a.size() == 3)
check("arr.element", a[1] == 2)

empty_arr = JSON.parse("\[\]")
check("arr.empty", empty_arr.size() == 0)

# --- nesting -----------------------------------------------------------------
nst = JSON.parse("{\"a\":{\"b\":\[10,20\]}}")
inner = nst["a"]["b"]
check("nested.type", type(inner) == "Array")
check("nested.value", inner[1] == 20)

arr_of_obj = JSON.parse("\[{\"k\":1},{\"k\":2}\]")
check("nested.array_of_objects", arr_of_obj[1]["k"] == 2)

# --- scalars -----------------------------------------------------------------
check("scalar.true", JSON.parse("true") == true)
check("scalar.false", JSON.parse("false") == false)
check("scalar.null", JSON.parse("null") == nil)
check("scalar.int", JSON.parse("7") == 7)
check("scalar.negative", JSON.parse("-7") == -7)
check("scalar.string", JSON.parse("\"s\"") == "s")

# --- escapes -----------------------------------------------------------------
esc = JSON.parse("{\"k\":\"a\\\"b\"}")
check("escape.embedded_quote", esc["k"] == "a\"b")

# --- round trip --------------------------------------------------------------
rt = JSON.parse(JSON.encode({x: 1}))
check("roundtrip.object", rt["x"] == 1)
