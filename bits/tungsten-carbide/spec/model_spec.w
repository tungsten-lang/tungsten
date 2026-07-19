# Carbide::Model specs — construction, validation, errors, to_h, and the
# in-memory store (create/find/all/where/update/destroy).
# Run: bin/tungsten bits/tungsten-carbide/spec/model_spec.w
# Also compiles: bin/tungsten -o <out> bits/tungsten-carbide/spec/model_spec.w

use spec
use carbide

+ SpecPost < Model
  -> table
    "spec_posts"

  -> title_length_error
    msg = nil
    t = get(:title)
    if t != nil && t != "" && t.to_s.size < 3
      msg = "title is too short"
    msg

  -> validations
    checks = []
    checks.push(Model.presence(:title))
    length_check = -> (m) m.title_length_error
    checks.push(Model.custom(:title, length_check))
    checks

# A second model with its own table — store isolation.
+ SpecTag < Model
  -> table
    "spec_tags"

describe "Model" ->
  describe "construction" ->
    it "builds from an attributes hash" ->
      p = SpecPost.new({title: "hello"})
      expect(p.get(:title)).to eq("hello")

    it "starts unpersisted with no id and no errors" ->
      p = SpecPost.new({title: "hello"})
      expect(p.persisted?).to be_false
      expect(p.new_record?).to be_true
      expect(p.id).to be_nil
      expect(p.errors.size).to eq(0)

    it "writes attributes with set" ->
      p = SpecPost.new({title: "hello"})
      p.set(:title, "changed")
      expect(p.get(:title)).to eq("changed")

  describe "validation" ->
    it "passes with valid attributes" ->
      p = SpecPost.new({title: "hello"})
      expect(p.valid?).to be_true

    it "fails presence on a missing attribute" ->
      p = SpecPost.new({})
      expect(p.valid?).to be_false

    it "collects the presence error message" ->
      p = SpecPost.new({})
      p.valid?
      expect(p.errors.size).to eq(1)
      expect(p.errors[0]).to eq("title can't be blank")

    it "runs custom lambda validators" ->
      p = SpecPost.new({title: "ab"})
      expect(p.valid?).to be_false
      expect(p.errors[0]).to eq("title is too short")

    it "clears stale errors on revalidation" ->
      p = SpecPost.new({})
      p.valid?
      p.set(:title, "hello")
      expect(p.valid?).to be_true
      expect(p.errors.size).to eq(0)

  describe "to_h" ->
    it "includes id and attributes" ->
      Model.reset_all
      p = Model.create(SpecPost, {title: "hello"})
      h = p.to_h
      expect(h[:id]).to eq(1)
      expect(h[:title]).to eq("hello")

    it "leaves id nil for an unsaved record" ->
      p = SpecPost.new({title: "hello"})
      expect(p.to_h[:id]).to be_nil

  describe "persistence" ->
    it "create persists a valid record" ->
      Model.reset_all
      p = Model.create(SpecPost, {title: "hello"})
      expect(p.persisted?).to be_true
      expect(p.id).to eq(1)
      expect(Model.count(SpecPost)).to eq(1)

    it "create keeps an invalid record unpersisted" ->
      Model.reset_all
      p = Model.create(SpecPost, {})
      expect(p.persisted?).to be_false
      expect(Model.count(SpecPost)).to eq(0)
      expect(p.errors[0]).to eq("title can't be blank")

    it "find returns the record by id" ->
      Model.reset_all
      Model.create(SpecPost, {title: "first"})
      q = Model.create(SpecPost, {title: "second"})
      found = Model.find(SpecPost, q.id)
      expect(found.get(:title)).to eq("second")

    it "find returns nil for a missing id" ->
      Model.reset_all
      expect(Model.find(SpecPost, 99)).to be_nil

    it "all returns every saved record" ->
      Model.reset_all
      Model.create(SpecPost, {title: "one"})
      Model.create(SpecPost, {title: "two"})
      expect(Model.all(SpecPost).size).to eq(2)

    it "where filters by attribute equality" ->
      Model.reset_all
      Model.create(SpecPost, {title: "keep", author: "amy"})
      Model.create(SpecPost, {title: "drop", author: "bob"})
      Model.create(SpecPost, {title: "keep", author: "bob"})
      hits = Model.where(SpecPost, {title: "keep"})
      expect(hits.size).to eq(2)
      both = Model.where(SpecPost, {title: "keep", author: "bob"})
      expect(both.size).to eq(1)
      expect(both[0].get(:author)).to eq("bob")

    it "update merges attributes and saves" ->
      Model.reset_all
      p = Model.create(SpecPost, {title: "old"})
      ok = p.update({title: "new"})
      expect(ok).to be_true
      expect(Model.find(SpecPost, p.id).get(:title)).to eq("new")

    it "update reports validation failure" ->
      Model.reset_all
      p = Model.create(SpecPost, {title: "fine"})
      ok = p.update({title: ""})
      expect(ok).to be_false
      expect(p.errors[0]).to eq("title can't be blank")

    it "destroy removes the record from the store" ->
      Model.reset_all
      p = Model.create(SpecPost, {title: "doomed"})
      p.destroy
      expect(p.persisted?).to be_false
      expect(Model.count(SpecPost)).to eq(0)
      expect(Model.find(SpecPost, p.id)).to be_nil

    it "isolates stores per table" ->
      Model.reset_all
      Model.create(SpecPost, {title: "hello"})
      Model.create(SpecTag, {name: "misc"})
      expect(Model.count(SpecPost)).to eq(1)
      expect(Model.count(SpecTag)).to eq(1)
      expect(Model.first(SpecTag).get(:name)).to eq("misc")

spec_summary
