# JSON.encode escapes strings built by concatenation.
#
# Regression: a long concatenation is a rope, a heap pointer whose low bits
# read as an empty inline string, so JSON's encoders scanned zero bytes and
# emitted `"` `\` and newlines raw: `"a" * 70 + " say \"hi\""` encoded as
# invalid JSON (compiled). The encoders now flatten a rope argument first, as
# String's own methods do for theirs.
#
# Run: `bin/tungsten spec/core/json_encode_rope_spec.w`
#      `bin/tungsten run --interpret spec/core/json_encode_rope_spec.w`

-> check(name, ok)
  if ok
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

-> built(text)
  out = ""
  i = 0
  while i < text.size
    out = out + text.slice(i, 1)
    i += 1
  out

pad = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
two = pad + " say \"hi\" and a back\\slash"
check("two-part concatenation escapes", JSON.encode(two).index("say \\\"hi\\\"") != nil)
check("two-part round-trips", JSON.parse(JSON.encode(two)) == two)

lines = pad + "\nline two\tand a tab"
check("newlines and tabs escape", JSON.encode(lines).index("\\nline two\\t") != nil)
check("newlines round-trip", JSON.parse(JSON.encode(lines)) == lines)

long = built(pad + " echo \"You've hit your weekly limit · resets Nov 1\"; exit 1")
check("char-by-char build round-trips", JSON.parse(JSON.encode(long)) == long)

nested = {"command" => two, "list" => [lines, long]}
nested[pad + "\"key\""] = 1
back = JSON.parse(JSON.encode(nested))
check("nested values round-trip", back["command"] == two && back["list"][0] == lines && back["list"][1] == long)
check("a concatenated key round-trips", back[pad + "\"key\""] == 1)
