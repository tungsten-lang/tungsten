# Carbide::Serializer specs — pure-Tungsten JSON encoding plus Model
# record/collection conveniences.
# Run: bin/tungsten bits/tungsten-carbide/spec/serializer_spec.w

use spec
use carbide

+ SerPost < Model
  -> table
    "ser_posts"

describe "Serializer" ->
  describe "encode" ->
    it "encodes integers" ->
      expect(Serializer.encode(5)).to eq("5")

    it "encodes strings with quotes" ->
      expect(Serializer.encode("hi")).to eq("\"hi\"")

    it "encodes booleans and nil" ->
      expect(Serializer.encode(true)).to eq("true")
      expect(Serializer.encode(false)).to eq("false")
      expect(Serializer.encode(nil)).to eq("null")

    it "encodes symbols as strings" ->
      expect(Serializer.encode(:ok)).to eq("\"ok\"")

    it "encodes arrays" ->
      expect(Serializer.encode([1, "a", nil])).to eq("\[1,\"a\",null\]")

    # Hash iteration is bucket order (identical across engines today,
    # but NOT insertion order and not guaranteed), so multi-key object
    # assertions check fragments instead of one exact string.
    it "encodes nested hashes" ->
      json = Serializer.encode({id: 1, tags: ["a"]})
      expect(json.starts_with?("{")).to be_true
      expect(json.include?("\"id\":1")).to be_true
      expect(json.include?("\"tags\":\[\"a\"\]")).to be_true

    it "escapes quotes, backslashes, and control characters" ->
      expect(Serializer.encode("a\"b\nc")).to eq("\"a\\\"b\\nc\"")
      expect(Serializer.encode("x\\y")).to eq("\"x\\\\y\"")

  describe "record and collection" ->
    it "serializes one model via to_h" ->
      Model.reset_all
      p = Model.create(SerPost, {title: "hi"})
      json = Serializer.record(p)
      expect(json.include?("\"id\":1")).to be_true
      expect(json.include?("\"title\":\"hi\"")).to be_true

    it "serializes a collection of models" ->
      Model.reset_all
      Model.create(SerPost, {title: "one"})
      Model.create(SerPost, {title: "two"})
      json = Serializer.collection(Model.all(SerPost))
      expect(json.starts_with?("\[{")).to be_true
      expect(json.include?("\"title\":\"one\"")).to be_true
      expect(json.include?("\"title\":\"two\"")).to be_true

spec_summary
