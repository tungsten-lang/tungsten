# Spec::Context — describe/context/it block hierarchy
# Contexts form a tree: each context holds examples (it blocks),
# nested contexts, hooks, and shared let bindings.

in Tungsten:Spec

+ Context
  ro :description
  ro :parent
  ro :children
  ro :examples
  ro :hooks
  ro :lets
  ro :tags

  -> new(@description, parent: nil, tags: [])
    @parent   = parent
    @children = []
    @examples = []
    @hooks    = Hooks.new
    @lets     = {}
    @tags     = tags

  # --- DSL methods (evaluated inside block) ---

  -> describe(desc, tags: [], &block)
    child = Context.new(desc, parent: ., tags: tags)
    child.instance_eval(&block)
    @children.push(child)
    child

  # context is an alias for describe
  -> context(desc, tags: [], &block)
    describe(desc, tags: tags, &block)

  # Define an example (test case)
  -> it(desc, tags: [], &block)
    example = Example.new(desc, context: ., block: block, tags: tags)
    @examples.push(example)
    example

  # Pending example — no block, or explicit pending
  -> pending(desc, &block)
    example = Example.new(desc, context: ., block: block, pending: true)
    @examples.push(example)
    example

  # Skip an example
  -> skip(desc, reason: nil)
    example = Example.new(desc, context: ., block: nil, skip: reason || true)
    @examples.push(example)

  # --- Let bindings (lazy memoized values) ---

  -> let(name, &block)
    @lets[name] = block

  -> let!(name, &block)
    # Eager let — evaluated in before_each
    @lets[name] = block
    before_each -> self.send(name)

  # --- Subject ---

  -> subject(&block)
    let(:subject, &block)

  # --- Hooks ---

  -> before_each(&block) = @hooks.add(:before_each, block)
  -> after_each(&block)  = @hooks.add(:after_each, block)
  -> before_all(&block)  = @hooks.add(:before_all, block)
  -> after_all(&block)   = @hooks.add(:after_all, block)

  # Convenience aliases
  -> before(&block) = before_each(&block)
  -> after(&block)  = after_each(&block)

  # --- Traversal ---

  # Collect all hooks of a type from root to this context
  -> collected_hooks(type)
    chain = ancestor_chain.map(ctx -> ctx.hooks.get(type))
    chain.flatten

  # Collect all let bindings from root to this context (child overrides parent)
  -> collected_lets
    ancestor_chain.reduce({}) -> (acc, ctx)
      acc.merge(ctx.lets)

  -> ancestor_chain
    chain = [.]
    current = @parent
    while current
      chain.unshift(current)
      current = current.parent
    chain

  # Full description path: "Calculator > addition > adds two numbers"
  -> full_description
    ancestor_chain.map(c -> c.description).join(" > ")

  # All examples including nested
  -> all_examples
    own = @examples
    nested = @children.flat_map(c -> c.all_examples)
    own + nested


# A single test case
+ Example
  ro :description
  ro :context
  ro :block
  ro :tags
  ro :pending
  ro :skip
  rw :result

  -> new(@description, context:, block: nil, tags: [], pending: false, skip: false)
    @context = context
    @block   = block
    @tags    = tags
    @pending = pending
    @skip    = skip
    @result  = nil

  -> full_description
    "#{@context.full_description} > #{@description}"

  -> runnable?
    !@pending && !@skip && @block

  -> run(env)
    return ExampleResult.skipped(@description) if @skip
    return ExampleResult.pending(@description) if @pending

    begin
      env.instance_eval(&@block)
      ExampleResult.passed(@description)
    rescue error
      ExampleResult.failed(@description, error)


+ ExampleResult
  ro :description
  ro :status
  ro :error

  -> new(@description, @status, @error = nil)

  -> passed?  = @status == :passed
  -> failed?  = @status == :failed
  -> pending? = @status == :pending
  -> skipped? = @status == :skipped

  -> .passed(desc)  = self.new(desc, :passed)
  -> .failed(desc, err) = self.new(desc, :failed, err)
  -> .pending(desc) = self.new(desc, :pending)
  -> .skipped(desc) = self.new(desc, :skipped)
