# tungsten-json contract spec.
#
# Runs the JSON parsing contract against the tungsten-json bit's
# SIMD-classifier-backed walker. `use tungsten-json` explicitly
# loads the bit, replacing core/json.w's recursive-descent .parse
# with the walker. The same contract should pass against core
# directly if you swap `use tungsten-json` for `use core/json`.
#
# String literal escapes in Tungsten: `[` and `]` inside a
# double-quoted string trigger `[expr]` interpolation, so JSON
# arrays in fixture strings must be written with `\[` and `\]`.

use tungsten-json

describe "JSON.parse — contract"
  it "parses an empty object"
    JSON.parse("{}") == {}

  it "parses an empty array"
    JSON.parse("\[\]") == []

  it "parses a simple object"
    JSON.parse("{\"a\":1}") == {"a" => 1}

  it "parses nested arrays"
    JSON.parse("\[1,\[2,\[3\]\]\]") == [1, [2, [3]]]

  it "parses nested objects"
    JSON.parse("{\"a\":{\"b\":{\"c\":1}}}") == {"a" => {"b" => {"c" => 1}}}

  it "parses booleans and null"
    JSON.parse("\[true, false, null\]") == [true, false, nil]

  it "parses numbers"
    JSON.parse("\[0, 42, -1, 3.14\]") == [0, 42, -1, 3.14]

  it "parses strings"
    JSON.parse("\"hello\"") == "hello"

  it "parses escape sequences"
    JSON.parse("\"line\\nbreak\"") == "line\nbreak"

  it "parses an object with mixed values"
    s = "{\"name\":\"Alice\",\"age\":30,\"tags\":\[\"admin\",\"user\"\],\"active\":true,\"nick\":null}"
    expected = {
      "name"   => "Alice",
      "age"    => 30,
      "tags"   => ["admin", "user"],
      "active" => true,
      "nick"   => nil
    }
    JSON.parse(s) == expected
