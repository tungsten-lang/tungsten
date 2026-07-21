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

# --- Model exercising query refinement (order/limit/offset/paginate/pluck).
# Carries a string :name and a numeric :priority so ordering by each key is
# unambiguous, and rows are inserted out of order so a working sort is visible.
+ SpecRanked < Model
  -> table
    "spec_ranked"

# --- Model exercising dirty tracking. No validations, so every save succeeds
# and the dirty state (changes/previous_changes/restore) is what's under test.
+ SpecDirty < Model
  -> table
    "spec_dirty"

# --- Models exercising lifecycle callbacks. SpecCB records every hook it fires
# into its :log attribute via #trace, so the full firing ORDER is one string to
# assert against (no wall-clock, no shared state).
+ SpecCB < Model
  -> table
    "spec_cb"
  -> before_validation
    [ -> (m) m.trace("bv") ]
  -> after_validation
    [ -> (m) m.trace("av") ]
  -> before_save
    [ -> (m) m.trace("bs") ]
  -> before_create
    [ -> (m) m.trace("bc") ]
  -> after_create
    [ -> (m) m.trace("ac") ]
  -> before_update
    [ -> (m) m.trace("bu") ]
  -> after_update
    [ -> (m) m.trace("au") ]
  -> after_save
    [ -> (m) m.trace("as") ]
  -> before_destroy
    [ -> (m) m.trace("bd") ]
  -> after_destroy
    [ -> (m) m.trace("ad") ]

  # Append a marker to the "-"-joined :log attribute.
  -> trace(mark)
    cur = get(:log)
    if cur == nil
      cur = ""
    if cur != ""
      cur = cur + "-"
    set(:log, cur + mark)

# before_validation normalizes a derived attribute so a presence check that
# would otherwise fail passes — proves the hook runs BEFORE the validators.
+ SpecSlug < Model
  -> table
    "spec_slug"
  -> before_validation
    [ -> (m) m.ensure_slug ]
  -> validations
    checks = []
    checks.push(Model.presence(:slug))
    checks
  -> ensure_slug
    if get(:slug) == nil
      set(:slug, "auto")
    nil

# before_save halts (returns false); after_save would set :ran but must not
# fire on the halted path — distinguishes a guard halt from a validation error.
+ SpecGuard < Model
  -> table
    "spec_guard"
  -> before_save
    [ -> (m) false ]
  -> after_save
    [ -> (m) m.set(:ran, true) ]

# before_destroy halts (returns false) — the record survives destroy.
+ SpecLocked < Model
  -> table
    "spec_locked"
  -> before_destroy
    [ -> (m) false ]

# after_save inspects the dirty-tracking state that the save just produced
# (R9 dovetail): the record is clean and previous_changes is populated.
+ SpecAfter < Model
  -> table
    "spec_after"
  -> after_save
    [ -> (m) m.capture_flags ]
  -> capture_flags
    set(:saw_clean, !changed?)
    set(:saw_prev, attribute_previously_changed?(:email))

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

  describe "query refinement" ->
    describe "order" ->
      it "sorts ascending by a string key" ->
        Model.reset_all
        Model.create(SpecRanked, {name: "charlie", priority: 2})
        Model.create(SpecRanked, {name: "alice", priority: 3})
        Model.create(SpecRanked, {name: "bob", priority: 1})
        rows = Model.order(Model.all(SpecRanked), :name)
        expect(rows[0].get(:name)).to eq("alice")
        expect(rows[1].get(:name)).to eq("bob")
        expect(rows[2].get(:name)).to eq("charlie")

      it "sorts descending with :desc" ->
        Model.reset_all
        Model.create(SpecRanked, {name: "charlie", priority: 2})
        Model.create(SpecRanked, {name: "alice", priority: 3})
        Model.create(SpecRanked, {name: "bob", priority: 1})
        rows = Model.order(Model.all(SpecRanked), :name, :desc)
        expect(rows[0].get(:name)).to eq("charlie")
        expect(rows[2].get(:name)).to eq("alice")

      it "sorts by a numeric key" ->
        Model.reset_all
        Model.create(SpecRanked, {name: "charlie", priority: 2})
        Model.create(SpecRanked, {name: "alice", priority: 3})
        Model.create(SpecRanked, {name: "bob", priority: 1})
        rows = Model.order(Model.all(SpecRanked), :priority)
        expect(rows[0].get(:name)).to eq("bob")
        expect(rows[2].get(:name)).to eq("alice")

      it "does not mutate the source array" ->
        Model.reset_all
        Model.create(SpecRanked, {name: "charlie", priority: 2})
        Model.create(SpecRanked, {name: "alice", priority: 3})
        src = Model.all(SpecRanked)
        Model.order(src, :name)
        expect(src[0].get(:name)).to eq("charlie")

    describe "limit / offset" ->
      it "limits to the first n rows" ->
        Model.reset_all
        Model.create(SpecRanked, {name: "a", priority: 1})
        Model.create(SpecRanked, {name: "b", priority: 2})
        Model.create(SpecRanked, {name: "c", priority: 3})
        rows = Model.order(Model.all(SpecRanked), :priority)
        limited = Model.limit(rows, 2)
        expect(limited.size).to eq(2)
        expect(limited[0].get(:name)).to eq("a")
        expect(limited[1].get(:name)).to eq("b")

      it "returns all rows when the limit exceeds the count" ->
        Model.reset_all
        Model.create(SpecRanked, {name: "a", priority: 1})
        Model.create(SpecRanked, {name: "b", priority: 2})
        expect(Model.limit(Model.all(SpecRanked), 10).size).to eq(2)

      it "treats a zero or negative limit as empty" ->
        Model.reset_all
        Model.create(SpecRanked, {name: "a", priority: 1})
        expect(Model.limit(Model.all(SpecRanked), 0).size).to eq(0)
        expect(Model.limit(Model.all(SpecRanked), -1).size).to eq(0)

      it "offsets past the first n rows" ->
        Model.reset_all
        Model.create(SpecRanked, {name: "a", priority: 1})
        Model.create(SpecRanked, {name: "b", priority: 2})
        Model.create(SpecRanked, {name: "c", priority: 3})
        rows = Model.order(Model.all(SpecRanked), :priority)
        rest = Model.offset(rows, 1)
        expect(rest.size).to eq(2)
        expect(rest[0].get(:name)).to eq("b")

      it "returns empty when the offset exceeds the count" ->
        Model.reset_all
        Model.create(SpecRanked, {name: "a", priority: 1})
        expect(Model.offset(Model.all(SpecRanked), 5).size).to eq(0)

    describe "paginate" ->
      it "returns the requested page" ->
        Model.reset_all
        Model.create(SpecRanked, {name: "a", priority: 1})
        Model.create(SpecRanked, {name: "b", priority: 2})
        Model.create(SpecRanked, {name: "c", priority: 3})
        Model.create(SpecRanked, {name: "d", priority: 4})
        Model.create(SpecRanked, {name: "e", priority: 5})
        rows = Model.order(Model.all(SpecRanked), :priority)
        page2 = Model.paginate(rows, 2, 2)
        expect(page2.size).to eq(2)
        expect(page2[0].get(:name)).to eq("c")
        expect(page2[1].get(:name)).to eq("d")

      it "returns a partial final page" ->
        Model.reset_all
        Model.create(SpecRanked, {name: "a", priority: 1})
        Model.create(SpecRanked, {name: "b", priority: 2})
        Model.create(SpecRanked, {name: "c", priority: 3})
        Model.create(SpecRanked, {name: "d", priority: 4})
        Model.create(SpecRanked, {name: "e", priority: 5})
        rows = Model.order(Model.all(SpecRanked), :priority)
        page3 = Model.paginate(rows, 3, 2)
        expect(page3.size).to eq(1)
        expect(page3[0].get(:name)).to eq("e")

      it "returns empty for an out-of-range page" ->
        Model.reset_all
        Model.create(SpecRanked, {name: "a", priority: 1})
        Model.create(SpecRanked, {name: "b", priority: 2})
        rows = Model.order(Model.all(SpecRanked), :priority)
        expect(Model.paginate(rows, 9, 2).size).to eq(0)

      it "clamps a page number below 1 to the first page" ->
        Model.reset_all
        Model.create(SpecRanked, {name: "a", priority: 1})
        Model.create(SpecRanked, {name: "b", priority: 2})
        rows = Model.order(Model.all(SpecRanked), :priority)
        page0 = Model.paginate(rows, 0, 2)
        expect(page0[0].get(:name)).to eq("a")

    describe "page_count" ->
      it "counts exact pages" ->
        expect(Model.page_count(10, 5)).to eq(2)

      it "rounds up a partial page" ->
        expect(Model.page_count(11, 5)).to eq(3)

      it "returns at least one page for zero rows" ->
        expect(Model.page_count(0, 5)).to eq(1)

    describe "pluck" ->
      it "extracts one attribute across rows in order" ->
        Model.reset_all
        Model.create(SpecRanked, {name: "a", priority: 1})
        Model.create(SpecRanked, {name: "b", priority: 2})
        rows = Model.order(Model.all(SpecRanked), :priority)
        names = Model.pluck(rows, :name)
        expect(names.size).to eq(2)
        expect(names[0]).to eq("a")
        expect(names[1]).to eq("b")

  describe "dirty tracking" ->
    it "reports a new record's set attributes as changed from nil" ->
      d = SpecDirty.new({name: "a"})
      expect(d.changed?).to be_true
      expect(d.changed.include?(:name)).to be_true
      expect(d.attribute_was(:name)).to be_nil

    it "records the old and new values in changes" ->
      d = SpecDirty.new({name: "a"})
      pair = d.changes[:name]
      expect(pair[0]).to be_nil
      expect(pair[1]).to eq("a")

    it "has empty previous_changes before any save" ->
      d = SpecDirty.new({name: "a"})
      expect(d.previous_changes.empty?).to be_true

    it "goes clean after a successful save" ->
      Model.reset_all
      d = Model.create(SpecDirty, {name: "a"})
      expect(d.changed?).to be_false
      expect(d.changed.size).to eq(0)

    it "tracks a change made after save" ->
      Model.reset_all
      d = Model.create(SpecDirty, {name: "a"})
      d.set(:name, "b")
      expect(d.changed?).to be_true
      expect(d.changes[:name][0]).to eq("a")
      expect(d.changes[:name][1]).to eq("b")

    it "answers attribute_was with the pre-change value" ->
      Model.reset_all
      d = Model.create(SpecDirty, {name: "a"})
      d.set(:name, "b")
      expect(d.attribute_was(:name)).to eq("a")

    it "answers attribute_changed? per attribute" ->
      Model.reset_all
      d = Model.create(SpecDirty, {name: "a", role: "x"})
      d.set(:name, "b")
      expect(d.attribute_changed?(:name)).to be_true
      expect(d.attribute_changed?(:role)).to be_false

    it "exposes changed_attributes as attr to original value" ->
      Model.reset_all
      d = Model.create(SpecDirty, {name: "a"})
      d.set(:name, "b")
      expect(d.changed_attributes[:name]).to eq("a")

    it "clears changes again after re-saving" ->
      Model.reset_all
      d = Model.create(SpecDirty, {name: "a"})
      d.set(:name, "b")
      d.save
      expect(d.changed?).to be_false

    it "records previous_changes from the last save" ->
      Model.reset_all
      d = Model.create(SpecDirty, {name: "a"})
      d.set(:name, "b")
      d.save
      expect(d.previous_changes[:name][0]).to eq("a")
      expect(d.previous_changes[:name][1]).to eq("b")

    it "answers attribute_previously_changed? after a save" ->
      Model.reset_all
      d = Model.create(SpecDirty, {name: "a"})
      d.set(:name, "b")
      d.save
      expect(d.attribute_previously_changed?(:name)).to be_true

    it "leaves previous_changes untouched on a no-op re-save" ->
      Model.reset_all
      d = Model.create(SpecDirty, {name: "a"})
      d.set(:name, "b")
      d.save
      d.save
      expect(d.previous_changes[:name][1]).to eq("b")

    it "reflects an update as a persisted change then goes clean" ->
      Model.reset_all
      d = Model.create(SpecDirty, {name: "a"})
      d.update({name: "c"})
      expect(d.changed?).to be_false
      expect(d.previous_changes[:name][1]).to eq("c")

    it "restore_attributes reverts unsaved changes to the baseline" ->
      Model.reset_all
      d = Model.create(SpecDirty, {name: "a"})
      d.set(:name, "b")
      d.restore_attributes
      expect(d.get(:name)).to eq("a")
      expect(d.changed?).to be_false

    it "restore_attributes drops attributes added since the baseline" ->
      Model.reset_all
      d = Model.create(SpecDirty, {name: "a"})
      d.set(:extra, "z")
      d.restore_attributes
      expect(d.get(:extra)).to be_nil

  describe "lifecycle callbacks" ->
    it "fires the save callbacks in Rails order on create" ->
      Model.reset_all
      c = Model.create(SpecCB, {})
      expect(c.get(:log)).to eq("bv-av-bs-bc-ac-as")

    it "fires the update callbacks instead of the create ones on a persisted save" ->
      Model.reset_all
      c = Model.create(SpecCB, {})
      c.set(:log, "")
      c.save
      expect(c.get(:log)).to eq("bv-av-bs-bu-au-as")

    it "runs before_validation before the validators (normalization)" ->
      Model.reset_all
      s = Model.create(SpecSlug, {})
      expect(s.persisted?).to be_true
      expect(s.get(:slug)).to eq("auto")

    it "halts the save when a before_save callback returns false" ->
      Model.reset_all
      g = Model.create(SpecGuard, {})
      expect(g.persisted?).to be_false
      expect(Model.count(SpecGuard)).to eq(0)

    it "treats a before_save halt as distinct from a validation failure" ->
      Model.reset_all
      g = Model.create(SpecGuard, {})
      expect(g.errors).to be_empty

    it "skips the after callbacks when a before_save halts" ->
      Model.reset_all
      g = Model.create(SpecGuard, {})
      expect(g.get(:ran)).to be_nil

    it "fires the destroy callbacks in order" ->
      Model.reset_all
      c = Model.create(SpecCB, {})
      c.set(:log, "")
      c.destroy
      expect(c.get(:log)).to eq("bd-ad")

    it "halts destroy when before_destroy returns false" ->
      Model.reset_all
      l = Model.create(SpecLocked, {})
      ok = l.destroy
      expect(ok).to be_false
      expect(l.persisted?).to be_true
      expect(Model.count(SpecLocked)).to eq(1)

    it "exposes clean state and previous_changes to after_save (dirty-tracking dovetail)" ->
      Model.reset_all
      a = Model.create(SpecAfter, {email: "a@x"})
      expect(a.get(:saw_clean)).to be_true
      expect(a.get(:saw_prev)).to be_true

spec_summary
