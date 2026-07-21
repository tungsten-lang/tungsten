# Carbide::Model — attribute models with validations and an in-memory store.
#
# The M in MVC, sized to what runs today: a model wraps a symbol-keyed
# attributes hash, validates itself (presence, length, numericality,
# inclusion, exclusion, and custom checks), and persists to a class-level
# in-memory store keyed by table name — enough for a controller to run the
# full CRUD loop without a database.
#
#   + Post < Model
#     -> table
#       "posts"
#     -> validations
#       checks = []
#       checks.push(Model.presence(:title))
#       checks.push(Model.custom(:title, -> (m) m.title_length_error))
#       checks
#
#   post = Model.create(Post, {title: "hello"})
#   post.persisted?                      # true
#   Model.find(Post, post.id)            # post
#   Model.where(Post, {title: "hello"})  # [post]
#
# Design notes (constraints verified by probe on BOTH engines — do not
# "clean up" without re-probing):
#   - The query API is Model.create(Post, attrs) / Model.find(Post, id)
#     / Model.all(Post) / Model.where(Post, conditions), NOT Post.create:
#     compiled binaries do not inherit class methods (interp does), so a
#     .create defined on Model is invisible on Post compiled. Classes are
#     first-class values and klass.new works in both engines (the same
#     pattern Route uses for controllers), so the class rides in as an
#     argument. A concrete model MAY add its own one-line class-method
#     shims (-> .create(attrs) Model.create(Post, attrs)) — direct class
#     methods work compiled; only inherited ones do not.
#   - Class variables are SHARED across the hierarchy (verified), so the
#     store is one registry on Model keyed by table name; each concrete
#     model overrides -> table. Instance methods and virtual dispatch
#     work identically in both engines, which is why table/validations
#     are instance methods rather than class-level DSL state.
#   - Attributes are symbol-keyed ({title: "x"}). Normalize string keys
#     (e.g. from JSON.parse) at the boundary with key.to_sym.
#   - Validations: -> validations returns descriptor hashes built with the
#     rule builders — Model.presence(attr), Model.length(attr, {min:,max:,
#     exact:}), Model.numericality(attr, {greater_than:, only_integer:, …}),
#     Model.inclusion(attr, {list:}), Model.exclusion(attr, {list:}), and
#     Model.custom(attr, check). A custom check lambda receives the MODEL and
#     returns nil (valid) or an error message string. Declarative rules read
#     their bounds/lists from an options hash; the allow-list key is :list
#     (`in` is a reserved word). Descriptors avoid the reserved word `fn` (the
#     lambda lives under :check) and lambdas are bound to a variable
#     before entering a hash literal (a bare `-> (v) ...` does not parse
#     as a hash-literal value).
#   - find returns nil for a missing id (no exceptions — identical
#     behavior in both engines beats raise/rescue divergence).
#   - Flag-style flow throughout: early `return` from a closure-bearing
#     method corrupts the self-hosted interpreter.
#
# Top-level (no `in` namespace): namespaced bit classes are unreachable
# from consumers and specs — same convention as route.w / controller.w.

+ Model
  ro :attributes
  ro :errors
  ro :id

  # table name -> array of saved instances / next auto-increment id.
  # One shared registry (class vars are hierarchy-shared); per-model
  # isolation comes from the table key.
  @@stores   = {}
  @@next_ids = {}

  # --- Store registry (class-side plumbing) ---

  -> .rows(table)
    if @@stores[table] == nil
      @@stores[table] = []
    @@stores[table]

  -> .replace_rows(table, rows)
    @@stores[table] = rows

  -> .allocate_id(table)
    current = @@next_ids[table]
    if current == nil
      current = 1
    @@next_ids[table] = current + 1
    current

  # Drop every table AND id sequence — spec isolation.
  -> .reset_all
    @@stores   = {}
    @@next_ids = {}

  # Table name for a model class: a blank instance answers #table
  # (instances virtual-dispatch identically in both engines; classes
  # do not).
  -> .table_of(klass)
    klass.new({}).table

  # --- Query interface: Model.create(Post, attrs), Model.find(Post, 3) ---

  -> .create(klass, attrs = {})
    record = klass.new(attrs)
    record.save
    record

  -> .all(klass)
    out = []
    Model.rows(Model.table_of(klass)).each -> (row)
      out.push(row)
    out

  -> .find(klass, id)
    found = nil
    Model.rows(Model.table_of(klass)).each -> (row)
      if found == nil && row.id == id
        found = row
    found

  -> .where(klass, conditions = {})
    out = []
    Model.rows(Model.table_of(klass)).each -> (row)
      if row.matches_conditions?(conditions)
        out.push(row)
    out

  -> .count(klass)
    Model.rows(Model.table_of(klass)).size

  -> .first(klass)
    rows = Model.rows(Model.table_of(klass))
    result = nil
    if rows.size > 0
      result = rows[0]
    result

  -> .delete_all(klass)
    Model.replace_rows(Model.table_of(klass), [])

  # --- Query refinement: order / limit / offset / paginate / pluck ---
  #
  # ActiveRecord chains order/limit/offset/page on a relation; carbide
  # composes them FUNCTIONALLY over the plain row array that all/where hand
  # back — each takes a rows array and returns a NEW array, never mutating
  # the store — because `where` yields an ordinary Array and collections ride
  # in as arguments (the same pragma create/find/where use: no relation
  # object, no inherited class methods to lose when compiled). They read
  # inside-out but compose cleanly, and every list action a web app needs
  # (sorted, paginated index pages) falls out of them:
  #
  #   rows  = Model.where(Post, {published: true})
  #   page2 = Model.paginate(Model.order(rows, :title), 2, 10)  # pg 2, 10/pg
  #   names = Model.pluck(page2, :title)                        # ["a", "b", …]
  #   pages = Model.page_count(Model.count(Post), 10)           # pager size
  #
  # Design notes (constraints verified by probe on BOTH engines):
  #   - Pure array slicing on top of sort_by/reverse/take/drop, all of which
  #     behave identically on both engines (sort_by honours its key block
  #     compiled, take/drop clamp to the array bounds rather than raising).
  #   - Ordering assumes a present, comparable key on every row (a column
  #     value), matching SQL ORDER BY; a nil or mixed-type key is a caller
  #     error, not defended here. limit/offset/paginate ARE nil- and
  #     over-range-safe: a bad page/size argument is clamped, an out-of-range
  #     page yields [] — a malformed ?page= param can't crash a list action.
  #   - Class methods called directly (Model.order(...)), never inherited, so
  #     they work compiled; the row array rides in as an argument.

  # Sort rows by attribute `key`. direction :asc (default) or :desc; :desc
  # reverses the ascending order.
  -> .order(rows, key, direction = :asc)
    sorted = rows.sort_by -> (row) row.get(key)
    result = sorted
    if direction == :desc
      result = sorted.reverse
    result

  # First `n` rows (SQL LIMIT). n >= size keeps them all; a nil or negative
  # n yields [].
  -> .limit(rows, n)
    count = n
    if count == nil || count < 0
      count = 0
    rows.take(count)

  # Skip the first `n` rows (SQL OFFSET). n >= size yields []; a nil or
  # negative n skips nothing.
  -> .offset(rows, n)
    skip = n
    if skip == nil || skip < 0
      skip = 0
    rows.drop(skip)

  # One page of results: 1-based page `number`, `per_page` rows each. An
  # out-of-range page yields [] (never raises); a nil/<1 number or per_page
  # is clamped to 1 so a bad param can't crash a list action.
  -> .paginate(rows, number, per_page)
    page = number
    if page == nil || page < 1
      page = 1
    size = per_page
    if size == nil || size < 1
      size = 1
    Model.limit(Model.offset(rows, (page - 1) * size), size)

  # How many pages `total` rows span at `per_page` each — for sizing a pager
  # UI (Kaminari's total_pages). Always >= 1; a nil/<1 per_page is clamped.
  -> .page_count(total, per_page)
    size = per_page
    if size == nil || size < 1
      size = 1
    pages = total / size
    if total % size != 0
      pages = pages + 1
    if pages < 1
      pages = 1
    pages

  # Extract one attribute across rows (SQL pluck): [row.get(key), ...],
  # in row order.
  -> .pluck(rows, key)
    out = []
    rows.each -> (row)
      out.push(row.get(key))
    out

  # --- Associations (Rails-style belongs_to / has_many / has_one) ---
  #
  # Relationships over the in-memory store, expressed as one-line
  # instance methods on a concrete model. A parent owns children through a
  # foreign-key attribute the child carries (child[:parent_id] == parent.id):
  #
  #   + Author < Model
  #     -> table
  #       "authors"
  #     -> books                                   # has_many
  #       Model.has_many(self, Book, :author_id)
  #     -> profile                                 # has_one
  #       Model.has_one(self, Profile, :author_id)
  #
  #   + Book < Model
  #     -> table
  #       "books"
  #     -> author                                  # belongs_to
  #       Model.belongs_to(self, Author, :author_id)
  #
  #   author.books        # [book, ...]  (every Book with author_id == author.id)
  #   author.profile      # profile or nil
  #   book.author         # author or nil
  #   book.author.id == author.id   # round-trips
  #
  # Design notes (same constraints as the query interface above):
  #   - Helper CLASS methods on Model, called from a concrete model's
  #     INSTANCE method. Inherited class methods are invisible to compiled
  #     binaries, but a direct Model.has_many(...) call is not inherited, and
  #     the target class rides in as an argument (classes are first-class
  #     values — the same pattern create/find/where use). Instance methods
  #     virtual-dispatch identically in both engines, so `author.books` works.
  #   - The foreign key is a symbol attribute name on the CHILD (:author_id).
  #     belongs_to reads it off the owner record; has_many/has_one match it
  #     against the parent's id.
  #   - No new store state: has_many/has_one filter through Model.where and
  #     belongs_to through Model.find, so associations inherit their nil/empty
  #     behavior — a nil or dangling foreign key yields nil (belongs_to/has_one)
  #     or [] (has_many), never an exception (identical on both engines).
  #   - Forward class references resolve at call time (verified on both
  #     engines), so a parent may name a child class defined later and the two
  #     sides may reference each other.

  # belongs_to: the single owner record this record points at through its
  # foreign_key attribute. nil when the key is unset or dangling.
  -> .belongs_to(record, owner_klass, foreign_key)
    Model.find(owner_klass, record.get(foreign_key))

  # has_many: every child record whose foreign_key equals this record's id
  # (an empty array when there are none).
  -> .has_many(owner, child_klass, foreign_key)
    conditions = {}
    conditions[foreign_key] = owner.id
    Model.where(child_klass, conditions)

  # has_one: the first child record whose foreign_key equals this record's
  # id, or nil when there are none.
  -> .has_one(owner, child_klass, foreign_key)
    matches = Model.has_many(owner, child_klass, foreign_key)
    result = nil
    if matches.size > 0
      result = matches[0]
    result

  # --- Validation descriptor builders ---

  # Presence: nil or "" fails with "<attr> can't be blank".
  -> .presence(attribute, options = {})
    {kind: :presence, attribute: attribute, message: options[:message]}

  # Custom: check.call(model) returns nil (valid) or an error message.
  -> .custom(attribute, check, options = {})
    {kind: :custom, attribute: attribute, check: check, message: options[:message]}

  # --- Declarative rule builders (Rails-style validations) ---
  #
  # All rule descriptors carry {kind:, attribute:, message:}; validation_error
  # dispatches on :kind. A :message option overrides the default text.
  # length/numericality SKIP a nil value (absent — let presence require it);
  # inclusion/exclusion evaluate every value (nil is simply not in the list).
  # No regex (format) rule: regex literals do not run on the interpreter, and
  # carbide must behave identically on both engines — use :custom for pattern
  # checks. Options are explicit hashes, not kwargs.

  # Length: {min:, max:, exact:} — e.g. Model.length(:title, {min: 3, max: 80}).
  # (`is` is a reserved word, so the exact-length key is :exact.)
  -> .length(attribute, options = {})
    {kind: :length, attribute: attribute, min: options[:min], max: options[:max], exact: options[:exact], message: options[:message]}

  # Numericality: value must be numeric, with optional bounds.
  # {only_integer:, greater_than:, greater_than_or_equal_to:, less_than:,
  #  less_than_or_equal_to:, equal_to:}.
  -> .numericality(attribute, options = {})
    {kind: :numericality, attribute: attribute, only_integer: options[:only_integer], greater_than: options[:greater_than], gte: options[:greater_than_or_equal_to], less_than: options[:less_than], lte: options[:less_than_or_equal_to], equal_to: options[:equal_to], message: options[:message]}

  # Inclusion: value must be one of {list: [...]} (`in` is a reserved word, so
  # the option key is :list). Missing list => nothing is allowed.
  -> .inclusion(attribute, options = {})
    allowed = options[:list]
    if allowed == nil
      allowed = []
    {kind: :inclusion, attribute: attribute, list: allowed, message: options[:message]}

  # Exclusion: value must NOT be one of {list: [...]}.
  -> .exclusion(attribute, options = {})
    forbidden = options[:list]
    if forbidden == nil
      forbidden = []
    {kind: :exclusion, attribute: attribute, list: forbidden, message: options[:message]}

  # --- Instance: construction and attribute access ---

  -> new(attrs = {})
    @attributes = {}
    own = @attributes
    seed = attrs
    if seed == nil
      seed = {}
    seed.each -> (k, v)
      own[k] = v
    @errors    = []
    @id        = nil
    @persisted = false
    # Dirty-tracking baselines (see the Dirty tracking section). A brand-new
    # record's clean baseline is empty, so every seeded attribute reads as a
    # change from nil until the first save snapshots the current state.
    @saved_attributes = {}
    @previous_changes = {}

  # Override in concrete models — the store key for this class.
  -> table
    "records"

  # Override in concrete models — array of validation descriptors.
  -> validations
    []

  -> get(name)
    @attributes[name]

  -> set(name, value)
    @attributes[name] = value

  # --- Validation ---

  # `me = self` before the block: inside a closure the interpreter
  # rebinds self to the iterated collection, so own-method calls (bare
  # or self.) don't resolve — an explicit local alias works identically
  # in both engines (verified by probe).
  -> valid?
    me = self
    run_hooks(before_validation)
    collected = []
    validations.each -> (v)
      msg = me.validation_error(v)
      if msg != nil
        collected.push(msg)
    @errors = collected
    run_hooks(after_validation)
    @errors.empty?

  # One descriptor -> nil or an error message string.
  #
  # :presence/:custom build the full message directly (custom's lambda owns
  # its text); the declarative rules return a bare suffix that is prefixed
  # with the attribute name here, matching presence's "<attr> can't be blank"
  # shape. A rule's own :message option, when present, replaces the default.
  -> validation_error(v)
    value = @attributes[v[:attribute]]
    kind = v[:kind]
    msg = nil
    suffix = nil
    if kind == :presence
      if value == nil || value == ""
        msg = v[:attribute].to_s + " can't be blank"
    elsif kind == :custom
      msg = v[:check].call(self)
    elsif kind == :length
      suffix = length_suffix(value, v)
    elsif kind == :numericality
      suffix = numericality_suffix(value, v)
    elsif kind == :inclusion
      unless v[:list].include?(value)
        suffix = "is not included in the list"
    elsif kind == :exclusion
      if v[:list].include?(value)
        suffix = "is reserved"
    if suffix != nil
      msg = v[:attribute].to_s + " " + suffix
    if msg != nil && v[:message] != nil
      msg = v[:message]
    msg

  # nil (valid) or a bare message suffix. A nil value is skipped — length is
  # about the shape of a present value; use presence to require it.
  -> length_suffix(value, v)
    msg = nil
    if value != nil
      len = value.to_s.size
      if v[:min] != nil && len < v[:min]
        msg = "is too short (minimum " + v[:min].to_s + " characters)"
      elsif v[:max] != nil && len > v[:max]
        msg = "is too long (maximum " + v[:max].to_s + " characters)"
      elsif v[:exact] != nil && len != v[:exact]
        msg = "is the wrong length (should be " + v[:exact].to_s + " characters)"
    msg

  # nil (valid) or a bare message suffix. A nil value is skipped (see above).
  # "Integer"/"Decimal" are the type() names for whole and fractional numbers.
  -> numericality_suffix(value, v)
    msg = nil
    if value != nil
      if type(value) != "Integer" && type(value) != "Decimal"
        msg = "is not a number"
      elsif v[:only_integer] != nil && type(value) != "Integer"
        msg = "must be an integer"
      elsif v[:greater_than] != nil && value <= v[:greater_than]
        msg = "must be greater than " + v[:greater_than].to_s
      elsif v[:gte] != nil && value < v[:gte]
        msg = "must be greater than or equal to " + v[:gte].to_s
      elsif v[:less_than] != nil && value >= v[:less_than]
        msg = "must be less than " + v[:less_than].to_s
      elsif v[:lte] != nil && value > v[:lte]
        msg = "must be less than or equal to " + v[:lte].to_s
      elsif v[:equal_to] != nil && value != v[:equal_to]
        msg = "must be equal to " + v[:equal_to].to_s
    msg

  # --- Lifecycle callbacks (ActiveRecord-style) ---
  #
  # Hooks fired around validation and persistence, declared exactly like
  # #validations: override a hook method to return an array of lambdas, each
  # taking the model. Every hook defaults to [] (no callback), so a model that
  # declares none behaves as before. Build the array inline or with push (both
  # parse for lambda literals).
  #
  #   + Post < Model
  #     -> before_validation
  #       [ -> (m) m.ensure_slug ]        # normalize before the validators run
  #     -> before_save
  #       [ -> (m) m.deny_if_locked ]     # guard: return false to abort the save
  #     -> after_create
  #       [ -> (m) m.notify_admins ]      # observe the fresh insert
  #
  # Firing order, matching Rails, on a successful save:
  #   before_validation -> (validate) -> after_validation ->
  #   before_save -> before_create|before_update -> (persist) ->
  #   after_create|after_update -> after_save
  # When validation fails the chain stops after after_validation (save false).
  # destroy fires: before_destroy -> (delete) -> after_destroy.
  #
  # Halting: a before_save / before_create / before_update / before_destroy
  # lambda returning exactly `false` ABORTS — persistence and every later
  # callback are skipped and the save/destroy returns false (Rails' throw
  # :abort). Any other return (nil, self, a string, …) continues. This mirrors
  # the controller's before-filter halt convention (controller.w). Validation
  # hooks (before/after_validation) are side-effect only — use them to
  # normalize attributes; require presence through #validations, not a hook.
  #
  # By the time the after_* callbacks run the record is already clean:
  # #changed? is false and #previous_changes holds what this save persisted
  # (dovetails with dirty tracking) — so after_save can ask "did :email change
  # on this save?" via attribute_previously_changed?.
  #
  # Design notes (same constraints as the rest of Model):
  #   - Instance methods returning lambda arrays, not class-level DSL — a symbol
  #     can't become a method call (Object#send is bodyless) and inherited class
  #     methods vanish when compiled. A lambda receives the model, so
  #     `-> (m) m.some_method` calls an instance method.
  #   - `me = self` before each `.each`: inside a closure the interpreter
  #     rebinds self, so the model must ride in through the alias.
  #   - Flag-style flow (no early return from a closure-bearing method).

  -> before_validation
    []
  -> after_validation
    []
  -> before_save
    []
  -> after_save
    []
  -> before_create
    []
  -> after_create
    []
  -> before_update
    []
  -> after_update
    []
  -> before_destroy
    []
  -> after_destroy
    []

  # Run a guard (before-style) callback array. Returns true to proceed, or
  # false if a callback halted by returning exactly `false`. Flag-style flow,
  # no early return (a bare return from a closure-bearing method corrupts the
  # interpreter).
  -> run_guard(callbacks)
    me = self
    ok = true
    callbacks.each -> (cb)
      if ok
        if cb.call(me) == false
          ok = false
    ok

  # Run a side-effect (after-style / validation) callback array. Return values
  # are ignored — these hooks observe or mutate, they do not halt.
  -> run_hooks(callbacks)
    me = self
    callbacks.each -> (cb)
      cb.call(me)
    nil

  # --- Persistence lifecycle ---

  -> save
    result = false
    proceed = valid?
    if proceed
      proceed = run_guard(before_save)
    # INSERT vs UPDATE decided before persist flips @persisted.
    created = !@persisted
    if proceed
      if created
        proceed = run_guard(before_create)
      else
        proceed = run_guard(before_update)
    if proceed
      if !@persisted
        @id = Model.allocate_id(table)
        Model.rows(table).push(self)
        @persisted = true
      result = true
      # Go clean BEFORE the after-callbacks so they observe Rails-consistent
      # state: capture what just changed into previous_changes (only when
      # something did — a no-op re-save leaves the prior previous_changes
      # untouched, matching Rails), then re-snapshot the current attributes as
      # the new clean baseline so #changed? reads false inside after_save.
      diff = changes
      if !diff.empty?
        @previous_changes = diff
      @saved_attributes = copy_hash(@attributes)
      if created
        run_hooks(after_create)
      else
        run_hooks(after_update)
      run_hooks(after_save)
    result

  # Merge attrs, then save. Returns save's result; attrs stay merged
  # even when validation fails (inspect #errors, fix, save again).
  -> update(attrs)
    own = @attributes
    attrs.each -> (k, v)
      own[k] = v
    save

  -> destroy
    result = false
    if run_guard(before_destroy)
      kept = []
      my_id = @id
      Model.rows(table).each -> (row)
        if row.id != my_id
          kept.push(row)
      Model.replace_rows(table, kept)
      @persisted = false
      result = true
      run_hooks(after_destroy)
    result

  -> new_record?
    !@persisted

  -> persisted?
    @persisted

  -> matches_conditions?(conditions)
    own = @attributes
    ok = true
    conditions.each -> (k, v)
      if own[k] != v
        ok = false
    ok

  # --- Dirty tracking (ActiveModel::Dirty subset) ---
  #
  # Which attributes differ from the last-saved (clean) state, computed by
  # diffing the live @attributes hash against a snapshot (@saved_attributes)
  # taken at construction ({} — so a new record's set attributes read as
  # changes from nil) and re-taken after every successful save. Nothing hooks
  # the setters: because the diff is derived lazily from the two hashes, it is
  # correct however an attribute was mutated — set, update, or the ctor seed:
  #
  #   post = Post.new({title: "a"})
  #   post.changed?              # true  (title: nil -> "a")
  #   post.save
  #   post.changed?              # false (baseline re-snapshotted)
  #   post.set(:title, "b")
  #   post.changed?              # true
  #   post.changes               # {title: ["a", "b"]}
  #   post.attribute_was(:title) # "a"
  #   post.save
  #   post.changed?              # false
  #   post.previous_changes      # {title: ["a", "b"]}
  #   post.attribute_previously_changed?(:title)  # true
  #
  # Design notes (same constraints as the rest of Model):
  #   - Snapshots are fresh copies (copy_hash), never aliases of @attributes —
  #     otherwise a later mutation would silently rewrite the baseline. The diff
  #     compares scalar attribute values with !=; an Array-valued attribute
  #     compares by identity (compiled Array == is identity), so an in-place
  #     array mutation is not detected — assign a new value to track it.
  #   - Attributes only ever grow (no attribute delete), so diffing over the
  #     live keys is complete; a value set to nil that had a baseline still
  #     registers as a change because the key is present.
  #   - previous_changes is only advanced when a save actually changed
  #     something; a no-op re-save leaves the previous save's record intact.

  # Fresh shallow copy of a hash — snapshots must not alias the live store.
  -> copy_hash(source)
    out = {}
    source.each -> (k, v)
      out[k] = v
    out

  # {attr => [old, new]} for every attribute differing from the clean baseline.
  -> changes
    base = @saved_attributes
    diff = {}
    @attributes.each -> (k, v)
      old = base[k]
      if old != v
        pair = []
        pair.push(old)
        pair.push(v)
        diff[k] = pair
    diff

  # Any unsaved change since the last clean state?
  -> changed?
    !changes.empty?

  # Names of the changed attributes, in attribute order.
  -> changed
    out = []
    changes.each -> (k, pair)
      out.push(k)
    out

  # {attr => original_value} — the pre-change value of each changed attribute.
  -> changed_attributes
    out = {}
    changes.each -> (k, pair)
      out[k] = pair[0]
    out

  # Has this specific attribute changed since the last clean state?
  -> attribute_changed?(name)
    found = false
    changes.each -> (k, pair)
      if k == name
        found = true
    found

  # The attribute's value as of the last clean state (its pre-change value when
  # dirty; the current value when unchanged). nil when never set/saved.
  -> attribute_was(name)
    @saved_attributes[name]

  # {attr => [old, new]} that the most recent successful save persisted — for
  # after-save logic ("did the email change on this save?").
  -> previous_changes
    @previous_changes

  # Did this attribute change on the most recent successful save?
  -> attribute_previously_changed?(name)
    found = false
    @previous_changes.each -> (k, pair)
      if k == name
        found = true
    found

  # Discard every unsaved change, reverting attributes to the clean baseline.
  # Returns self.
  -> restore_attributes
    @attributes = copy_hash(@saved_attributes)
    self

  # --- Serialization ---

  -> to_h
    h = {}
    h[:id] = @id
    @attributes.each -> (k, v)
      h[k] = v
    h
