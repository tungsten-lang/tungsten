# Carbide::Validator — reusable validation objects
# Define standalone validators that can be used across models and forms.

in Tungsten:Carbide

+ Validator
  ro :options

  -> new(**options)
    @options = options

  # Override in subclasses — return nil for valid, error message string for invalid
  -> validate(value)
    <! "Validator#validate must be implemented"

  # Convenience: returns true/false
  -> valid?(value)
    self.validate(value).nil?

  # --- Class-level shortcut ---

  -> .validate(value, **options)
    self.new(**options).validate(value)


  # --- Built-in validators ---

  + PresenceValidator < Validator
    -> validate(value)
      if value.nil? || value == "" || (value.respond_to?(:empty?) && value.empty?)
        @options[:message] || "can't be blank"
      else
        nil

  + LengthValidator < Validator
    -> validate(value)
      len = value.to_s.size
      min = @options[:min]
      max = @options[:max]

      if min && len < min
        @options[:message] || "is too short (minimum #{min} characters)"
      elsif max && len > max
        @options[:message] || "is too long (maximum #{max} characters)"
      else
        nil

  + FormatValidator < Validator
    -> validate(value)
      pattern = @options[:pattern] || @options[:with]
      unless value.to_s.match?(pattern)
        @options[:message] || "is invalid"

  + InclusionValidator < Validator
    -> validate(value)
      allowed = @options[:in] || []
      unless allowed.include?(value)
        @options[:message] || "is not included in the list"

  + NumericalityValidator < Validator
    -> validate(value)
      unless value.is_a?(Numeric)
        << (@options[:message] || "is not a number")

      if @options[:greater_than] && value <= @options[:greater_than]
        << "must be greater than #{@options[:greater_than]}"
      if @options[:less_than] && value >= @options[:less_than]
        << "must be less than #{@options[:less_than]}"
      nil

  + UniquenessValidator < Validator
    -> validate(value)
      model_class = @options[:scope]
      field = @options[:field]
      if model_class && field && model_class.exists?(field => value)
        @options[:message] || "has already been taken"
      else
        nil

  + EmailValidator < Validator
    EMAIL_PATTERN = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

    -> validate(value)
      unless value.to_s.match?(EMAIL_PATTERN)
        @options[:message] || "is not a valid email address"

  + URLValidator < Validator
    URL_PATTERN = /\Ahttps?:\/\/[^\s]+\z/

    -> validate(value)
      unless value.to_s.match?(URL_PATTERN)
        @options[:message] || "is not a valid URL"


  # --- Validation set: compose multiple validators ---

  + Set
    ro :validators

    -> new
      @validators = []

    -> add(validator)
      @validators.push(validator)
      self

    -> validate(value)
      errors = []
      @validators.each -> (v)
        error = v.validate(value)
        errors.push(error) if error
      if errors.empty? then nil else errors
