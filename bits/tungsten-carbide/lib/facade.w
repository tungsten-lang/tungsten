# Carbide::Facade — clean interface over complex subsystems
# Encapsulates multi-step operations behind a single `call` method.
# Returns a Result object for consistent success/failure handling.

in Tungsten:Carbide

+ Facade
  ro :params
  ro :context

  -> new(**params)
    @params  = params
    @context = {}

  # Override in subclasses — the main operation
  -> call
    <! "Facade#call must be implemented"

  # --- Class-level convenience ---

  -> .call(**params)
    facade = self.new(**params)
    begin
      result = facade.call
      Result.success(result)
    rescue error
      Result.failure(error.message)

  # --- Result helpers ---

  -> succeed(value = nil)
    Result.success(value)

  -> fail(message)
    Result.failure(message)

  # --- Step composition ---
  # Chain multiple steps; halt on first failure

  -> step(name, &block)
    result = block.call(@context)
    if result.is_a?(Result) && result.failure?
      <! StepFailure.new(name, result.error)
    @context[name] = result
    result

  + StepFailure < StandardError
    ro :step_name
    ro :error

    -> new(@step_name, @error)
      super("Step '#{@step_name}' failed: #{@error}")


  # --- Result type ---

  + Result
    ro :value
    ro :error
    ro :success

    -> .success(value = nil)
      self.new(value: value, error: nil, success: true)

    -> .failure(error)
      self.new(value: nil, error: error, success: false)

    -> new(value:, error:, success:)
      @value   = value
      @error   = error
      @success = success

    -> success?
      @success

    -> failure?
      !@success

    -> then(&block)
      if self.success?
        result = block.call(@value)
        if result.is_a?(Result) then result else Result.success(result)
      else
        self

    -> or_else(&block)
      if self.failure?
        block.call(@error)
      else
        self

    -> unwrap!
      <! @error if self.failure?
      @value
