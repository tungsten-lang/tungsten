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
    collected = []
    validations.each -> (v)
      msg = me.validation_error(v)
      if msg != nil
        collected.push(msg)
    @errors = collected
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

  # --- Persistence lifecycle ---

  -> save
    result = false
    if valid?
      if !@persisted
        @id = Model.allocate_id(table)
        Model.rows(table).push(self)
        @persisted = true
      result = true
    result

  # Merge attrs, then save. Returns save's result; attrs stay merged
  # even when validation fails (inspect #errors, fix, save again).
  -> update(attrs)
    own = @attributes
    attrs.each -> (k, v)
      own[k] = v
    save

  -> destroy
    kept = []
    my_id = @id
    Model.rows(table).each -> (row)
      if row.id != my_id
        kept.push(row)
    Model.replace_rows(table, kept)
    @persisted = false
    true

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

  # --- Serialization ---

  -> to_h
    h = {}
    h[:id] = @id
    @attributes.each -> (k, v)
      h[k] = v
    h
