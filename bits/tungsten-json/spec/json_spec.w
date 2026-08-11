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

use spec
use tungsten-json

describe "JSON.parse — contract" ->
  it "parses an empty object" ->
    expect(JSON.parse("{}")).to eq({})

  it "parses an empty array" ->
    expect(JSON.parse("\[\]")).to eq([])

  it "parses a simple object" ->
    expect(JSON.parse("{\"a\":1}")).to eq({"a" => 1})

  it "parses nested arrays" ->
    expect(JSON.parse("\[1,\[2,\[3\]\]\]")).to eq([1, [2, [3]]])

  it "parses nested objects" ->
    expect(JSON.parse("{\"a\":{\"b\":{\"c\":1}}}")).to eq({"a" => {"b" => {"c" => 1}}})

  it "parses booleans and null" ->
    expect(JSON.parse("\[true, false, null\]")).to eq([true, false, nil])

  it "parses numbers" ->
    expect(JSON.parse("\[0, 42, -1, 3.14\]")).to eq([0, 42, -1, ~3.14])

  it "parses strings" ->
    expect(JSON.parse("\"hello\"")).to eq("hello")

  it "parses escape sequences" ->
    expect(JSON.parse("\"line\\nbreak\"")).to eq("line\nbreak")

  it "parses an object with mixed values" ->
    s = "{\"name\":\"Alice\",\"age\":30,\"tags\":\[\"admin\",\"user\"\],\"active\":true,\"nick\":null}"
    expected = {
      "name"   => "Alice",
      "age"    => 30,
      "tags"   => ["admin", "user"],
      "active" => true,
      "nick"   => nil
    }
    expect(JSON.parse(s)).to eq(expected)

spec_summary
