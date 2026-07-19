# Carbide::Model — attribute models with validations and an in-memory store.
#
# The M in MVC, sized to what runs today: a model wraps a symbol-keyed
# attributes hash, validates itself (presence + custom checks), and
# persists to a class-level in-memory store keyed by table name — enough
# for a controller to run the full CRUD loop without a database.
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
#   - Validations: -> validations returns descriptor hashes built with
#     Model.presence(attr) / Model.custom(attr, check). A custom check
#     lambda receives the MODEL and returns nil (valid) or an error
#     message string. Descriptors avoid the reserved word `fn` (the
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

  # --- Validation descriptor builders ---

  # Presence: nil or "" fails with "<attr> can't be blank".
  -> .presence(attribute, options = {})
    {kind: :presence, attribute: attribute, message: options[:message]}

  # Custom: check.call(model) returns nil (valid) or an error message.
  -> .custom(attribute, check, options = {})
    {kind: :custom, attribute: attribute, check: check, message: options[:message]}

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
  -> validation_error(v)
    value = @attributes[v[:attribute]]
    msg = nil
    if v[:kind] == :presence
      if value == nil || value == ""
        msg = v[:attribute].to_s + " can't be blank"
    elsif v[:kind] == :custom
      msg = v[:check].call(self)
    if msg != nil && v[:message] != nil
      msg = v[:message]
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
