# Carbide::Config — typed configuration
# Define config schema with types and defaults, load from environment, validate.

in Tungsten:Carbide

+ Config
  ro :values
  ro :schema

  @@schemas = {}

  # --- Class-level DSL ---

  -> .setting(name, type: :string, default: nil, required: false, env: nil)
    @@schemas[name] = {
      type: type,
      default: default,
      required: required,
      env: env || name.to_s.upcase
    }

    # Define getter
    define_method(name) ->
      @values[name]

    # Define setter
    define_method("#{name}=") -> (value)
      @values[name] = self.cast(name, value)

  -> .schema
    @@schemas

  # --- Instance ---

  -> new
    @schema = @@schemas.dup
    @values = {}
    self.load_defaults
    self.load_environment

  -> load_defaults
    @schema.each -> (name, opts)
      @values[name] = opts[:default] if opts[:default]

  -> load_environment
    @schema.each -> (name, opts)
      env_value = ENV[opts[:env]]
      if env_value
        @values[name] = self.cast(name, env_value)

  -> validate!
    errors = []
    @schema.each -> (name, opts)
      if opts[:required] && @values[name].nil?
        errors.push("#{name} is required")
    if errors.any?
      <! ConfigError.new("Configuration invalid: #{errors.join(', ')}")
    true

  -> cast(name, value)
    opts = @schema[name]
    << value unless opts
    case opts[:type]
      :string  => value.to_s
      :integer => value.to_i
      :float   => value.to_f
      :boolean => ["true", "1", "yes"].include?(value.to_s.downcase)
      :symbol  => value.to_sym
      :array   => if value.is_a?(String) then value.split(",").map(-> (s) s.strip) else value
      => value

  -> [](key)
    @values[key]

  -> []=(key, value)
    @values[key] = self.cast(key, value)

  -> to_h
    @values.dup

  -> merge(**overrides)
    overrides.each -> (key, value)
      @values[key] = self.cast(key, value)
    self

  # --- Environment-aware loading ---

  -> .for_environment(env = nil)
    env ||= ENV["TUNGSTEN_ENV"] || "development"
    config = self.new
    config.merge(environment: env)
    config

  + ConfigError < StandardError
