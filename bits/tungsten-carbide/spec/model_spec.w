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

# --- Models exercising the declarative validation rules (one rule each so a
# failing spec points at exactly one descriptor). ---

+ SpecLen < Model
  -> table
    "spec_len"
  -> validations
    checks = []
    checks.push(Model.length(:code, {min: 3, max: 6}))
    checks

+ SpecExact < Model
  -> table
    "spec_exact"
  -> validations
    checks = []
    checks.push(Model.length(:pin, {exact: 4}))
    checks

+ SpecNum < Model
  -> table
    "spec_num"
  -> validations
    checks = []
    checks.push(Model.numericality(:age, {only_integer: true, greater_than: 0, less_than: 150}))
    checks

+ SpecInc < Model
  -> table
    "spec_inc"
  -> validations
    checks = []
    checks.push(Model.inclusion(:role, {list: ["admin", "user"]}))
    checks

+ SpecExc < Model
  -> table
    "spec_exc"
  -> validations
    checks = []
    checks.push(Model.exclusion(:name, {list: ["admin", "root"]}))
    checks

+ SpecMsg < Model
  -> table
    "spec_msg"
  -> validations
    checks = []
    checks.push(Model.length(:code, {min: 5, message: "code too tiny"}))
    checks

# --- Models exercising associations. A SpecAuthor has_many SpecBooks and
# has_one SpecProfile; each child belongs_to its SpecAuthor via :author_id.
# The two sides reference each other (forward class refs resolve at call
# time on both engines).
+ SpecAuthor < Model
  -> table
    "spec_authors"
  -> books
    Model.has_many(self, SpecBook, :author_id)
  -> profile
    Model.has_one(self, SpecProfile, :author_id)

+ SpecBook < Model
  -> table
    "spec_books"
  -> author
    Model.belongs_to(self, SpecAuthor, :author_id)

+ SpecProfile < Model
  -> table
    "spec_profiles"
  -> author
    Model.belongs_to(self, SpecAuthor, :author_id)

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

  describe "declarative validations" ->
    describe "length" ->
      it "accepts a value within min/max" ->
        expect(SpecLen.new({code: "abcd"}).valid?).to be_true

      it "rejects a value shorter than min" ->
        m = SpecLen.new({code: "ab"})
        expect(m.valid?).to be_false
        expect(m.errors[0]).to eq("code is too short (minimum 3 characters)")

      it "rejects a value longer than max" ->
        m = SpecLen.new({code: "abcdefg"})
        expect(m.valid?).to be_false
        expect(m.errors[0]).to eq("code is too long (maximum 6 characters)")

      it "skips length on a nil value (presence's job)" ->
        expect(SpecLen.new({}).valid?).to be_true

      it "enforces an exact length" ->
        m = SpecExact.new({pin: "12"})
        expect(m.valid?).to be_false
        expect(m.errors[0]).to eq("pin is the wrong length (should be 4 characters)")
        expect(SpecExact.new({pin: "1234"}).valid?).to be_true

    describe "numericality" ->
      it "accepts a valid integer in range" ->
        expect(SpecNum.new({age: 30}).valid?).to be_true

      it "rejects a non-numeric value" ->
        m = SpecNum.new({age: "old"})
        expect(m.valid?).to be_false
        expect(m.errors[0]).to eq("age is not a number")

      it "rejects a non-integer when only_integer is set" ->
        m = SpecNum.new({age: 3.5})
        expect(m.valid?).to be_false
        expect(m.errors[0]).to eq("age must be an integer")

      it "enforces greater_than" ->
        m = SpecNum.new({age: 0})
        expect(m.valid?).to be_false
        expect(m.errors[0]).to eq("age must be greater than 0")

      it "enforces less_than" ->
        m = SpecNum.new({age: 200})
        expect(m.valid?).to be_false
        expect(m.errors[0]).to eq("age must be less than 150")

      it "skips numericality on a nil value" ->
        expect(SpecNum.new({}).valid?).to be_true

    describe "inclusion / exclusion" ->
      it "accepts a listed value" ->
        expect(SpecInc.new({role: "admin"}).valid?).to be_true

      it "rejects an unlisted value" ->
        m = SpecInc.new({role: "ghost"})
        expect(m.valid?).to be_false
        expect(m.errors[0]).to eq("role is not included in the list")

      it "rejects a reserved value" ->
        m = SpecExc.new({name: "admin"})
        expect(m.valid?).to be_false
        expect(m.errors[0]).to eq("name is reserved")

      it "accepts a non-reserved value" ->
        expect(SpecExc.new({name: "alice"}).valid?).to be_true

    describe "message override" ->
      it "replaces the default text with a rule's :message" ->
        m = SpecMsg.new({code: "ab"})
        expect(m.valid?).to be_false
        expect(m.errors[0]).to eq("code too tiny")

  describe "associations" ->
    describe "belongs_to" ->
      it "returns the owner record via the foreign key" ->
        Model.reset_all
        a = Model.create(SpecAuthor, {name: "amy"})
        b = Model.create(SpecBook, {title: "hello", author_id: a.id})
        expect(b.author.get(:name)).to eq("amy")
        expect(b.author.id).to eq(a.id)

      it "returns nil when the foreign key is unset" ->
        Model.reset_all
        b = Model.create(SpecBook, {title: "orphan"})
        expect(b.author).to be_nil

      it "returns nil for a dangling foreign key" ->
        Model.reset_all
        b = Model.create(SpecBook, {title: "ghost", author_id: 999})
        expect(b.author).to be_nil

    describe "has_many" ->
      it "returns every child pointing at this record" ->
        Model.reset_all
        a = Model.create(SpecAuthor, {name: "amy"})
        Model.create(SpecBook, {title: "one", author_id: a.id})
        Model.create(SpecBook, {title: "two", author_id: a.id})
        expect(a.books.size).to eq(2)

      it "returns an empty array when there are no children" ->
        Model.reset_all
        a = Model.create(SpecAuthor, {name: "amy"})
        expect(a.books.size).to eq(0)

      it "scopes children to their own owner" ->
        Model.reset_all
        a = Model.create(SpecAuthor, {name: "amy"})
        b = Model.create(SpecAuthor, {name: "bob"})
        Model.create(SpecBook, {title: "a1", author_id: a.id})
        Model.create(SpecBook, {title: "a2", author_id: a.id})
        Model.create(SpecBook, {title: "b1", author_id: b.id})
        expect(a.books.size).to eq(2)
        expect(b.books.size).to eq(1)
        expect(b.books[0].get(:title)).to eq("b1")

      it "round-trips has_many back to belongs_to" ->
        Model.reset_all
        a = Model.create(SpecAuthor, {name: "amy"})
        Model.create(SpecBook, {title: "solo", author_id: a.id})
        book = a.books[0]
        expect(book.author.id).to eq(a.id)

    describe "has_one" ->
      it "returns the single child record" ->
        Model.reset_all
        a = Model.create(SpecAuthor, {name: "amy"})
        Model.create(SpecProfile, {bio: "writes code", author_id: a.id})
        expect(a.profile.get(:bio)).to eq("writes code")

      it "returns nil when there is no child" ->
        Model.reset_all
        a = Model.create(SpecAuthor, {name: "amy"})
        expect(a.profile).to be_nil

spec_summary
