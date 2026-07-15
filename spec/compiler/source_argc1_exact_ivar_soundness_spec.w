+ ProofTarget
  -> argc1(value)
    value

+ UnknownWriteHolder
  -> new
    @receiver = ProofTarget.new()

  -> replace(value)
    @receiver = value

  -> call(value)
    @receiver.argc1(value)

+ CompoundWriteHolder
  -> new
    @receiver = ProofTarget.new()

  -> mutate(value)
    @receiver += value

  -> call(value)
    @receiver.argc1(value)

+ MultiWriteHolder
  -> new
    @receiver = ProofTarget.new()

  -> replace(values)
    @receiver, other = values

  -> call(value)
    @receiver.argc1(value)

+ ImplicitWriteHolder
  -> new(@receiver)

  -> reset
    @receiver = ProofTarget.new()

  -> call(value)
    @receiver.argc1(value)

+ AccessorWriteHolder
  rw :receiver

  -> new
    @receiver = ProofTarget.new()

  -> call(value)
    @receiver.argc1(value)

+ ReopenedWriteHolder
  -> new
    @receiver = ProofTarget.new()

+ ReopenedWriteHolder
  -> replace(value)
    @receiver = value

  -> call(value)
    @receiver.argc1(value)

+ BaseWriteHolder
  -> replace(value)
    @receiver = value

+ InheritedWriteHolder < BaseWriteHolder
  -> new
    @receiver = ProofTarget.new()

  -> call(value)
    @receiver.argc1(value)

+ BaseExactHolder
  -> new
    @receiver = ProofTarget.new()

  -> call(value)
    @receiver.argc1(value)

+ DescendantWriteHolder < BaseExactHolder
  -> replace(value)
    @receiver = value

+ HintedWriteHolder
  -> new
    @receiver = ProofTarget.new()

  -> replace(value)
    @receiver = value ## ProofTarget

  -> call(value)
    @receiver.argc1(value)
