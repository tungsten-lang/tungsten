# Carbide::Model — attributes, validations, associations, callbacks, and scopes
# Models are the M in MVC. They wrap database records with domain logic.

in Tungsten:Carbide

trait Validatable
  -> validate
    errors = []
    self.class.validations.each -> (v)
      result = run_validation(v)
      errors.push(result) if result
    errors

  -> valid?
    validate.empty?

  -> run_validation(v)
    value = self.send(v.attribute)
    case v.kind
      :presence  => "#{v.attribute} can't be blank" if value.nil? || value == ""
      :length    =>
        len = value.to_s.size
        if v.options[:min] && len < v.options[:min]
          "#{v.attribute} is too short (minimum #{v.options[:min]})"
        elsif v.options[:max] && len > v.options[:max]
          "#{v.attribute} is too long (maximum #{v.options[:max]})"
      :format    => "#{v.attribute} is invalid" unless value.to_s.match?(v.options[:with])
      :inclusion => "#{v.attribute} is not included in the list" unless v.options[:in].include?(value)
      :numericality => "#{v.attribute} is not a number" unless value.is_a?(Numeric)
      :uniqueness   => "#{v.attribute} has already been taken" if self.class.exists?(v.attribute => value)
      :custom        => v.options[:block].call(self, value)


trait Associable
  -> .belongs_to(name, class_name: nil, foreign_key: nil)
    fk = foreign_key || "#{name}_id"
    klass = class_name || name.to_s.classify

    # Define getter: look up parent by foreign key
    define_method(name) ->
      Object.const_get(klass).find(self.send(fk))

  -> .has_many(name, class_name: nil, foreign_key: nil)
    fk = foreign_key || "#{self.name.underscore}_id"
    klass = class_name || name.to_s.singularize.classify

    define_method(name) ->
      Object.const_get(klass).where(fk => self.id)

  -> .has_one(name, class_name: nil, foreign_key: nil)
    fk = foreign_key || "#{self.name.underscore}_id"
    klass = class_name || name.to_s.classify

    define_method(name) ->
      Object.const_get(klass).find_by(fk => self.id)


+ Model
  use Validatable
  use Associable

  ro :id
  ro :attributes
  ro :errors
  ro :persisted
  ro :changed_attributes

  # Class-level storage
  @@table_name   = nil
  @@validations  = []
  @@callbacks    = {
    before_save:    [],
    after_save:     [],
    before_create:  [],
    after_create:   [],
    before_update:  [],
    after_update:   [],
    before_destroy: [],
    after_destroy:  []
  }
  @@scopes = {}

  # --- Schema DSL (class-level) ---

  -> .table_name(name = nil)
    if name
      @@table_name = name
    else
      @@table_name || self.name.underscore.pluralize

  -> .attribute(name, type: :string, default: nil)
    define_method(name)       -> @attributes[name] || default
    define_method("#{name}=") -> (value)
      @changed_attributes[name] = @attributes[name]
      @attributes[name] = value

  -> .validations
    @@validations

  -> .validates(attribute, **options)
    options.each -> (kind, opts)
      validation = case opts
        true => {attribute: attribute, kind: kind, options: {}}
        Hash => {attribute: attribute, kind: kind, options: opts}
        =>    {attribute: attribute, kind: kind, options: {}}
      @@validations.push(validation)

  # --- Callbacks ---

  -> .before_save(method_name)    = @@callbacks[:before_save].push(method_name)
  -> .after_save(method_name)     = @@callbacks[:after_save].push(method_name)
  -> .before_create(method_name)  = @@callbacks[:before_create].push(method_name)
  -> .after_create(method_name)   = @@callbacks[:after_create].push(method_name)
  -> .before_update(method_name)  = @@callbacks[:before_update].push(method_name)
  -> .after_update(method_name)   = @@callbacks[:after_update].push(method_name)
  -> .before_destroy(method_name) = @@callbacks[:before_destroy].push(method_name)
  -> .after_destroy(method_name)  = @@callbacks[:after_destroy].push(method_name)

  # --- Scopes ---

  -> .scope(name, query_fn)
    @@scopes[name] = query_fn
    define_singleton_method(name) -> (*args)
      query_fn.call(*args)

  # --- Query interface ---

  -> .all
    Query.new(self.table_name)

  -> .where(**conditions)
    all.where(**conditions)

  -> .find(id)
    all.where(id: id).first || <! RecordNotFound.new("#{self.name} not found: #{id}")

  -> .find_by(**conditions)
    all.where(**conditions).first

  -> .exists?(**conditions)
    all.where(**conditions).exists?

  -> .count
    all.count

  -> .first  = all.first
  -> .last   = all.last

  # --- Instance lifecycle ---

  -> new(attrs = {})
    @attributes         = attrs
    @errors             = []
    @persisted          = false
    @changed_attributes = {}

  -> save
    return false unless valid?

    if @persisted
      run_callbacks(:before_update)
      run_callbacks(:before_save)
      self.class.adapter.update(self.class.table_name, @id, @attributes)
      run_callbacks(:after_save)
      run_callbacks(:after_update)
    else
      run_callbacks(:before_create)
      run_callbacks(:before_save)
      @id = self.class.adapter.insert(self.class.table_name, @attributes)
      @persisted = true
      run_callbacks(:after_save)
      run_callbacks(:after_create)

    @changed_attributes = {}
    true

  -> save!
    save || <! RecordInvalid.new("Validation failed: #{errors.join(', ')}")

  -> update(attrs)
    attrs.each -> (key, value)
      self.send("#{key}=", value)
    save

  -> destroy
    run_callbacks(:before_destroy)
    self.class.adapter.delete(self.class.table_name, @id)
    @persisted = false
    run_callbacks(:after_destroy)
    self.freeze

  -> new_record?  = !@persisted
  -> persisted?   = @persisted
  -> changed?     = @changed_attributes.any?

  -> run_callbacks(kind)
    @@callbacks[kind].each -> (method_name)
      self.send(method_name)


+ RecordNotFound < StandardError
+ RecordInvalid  < StandardError
