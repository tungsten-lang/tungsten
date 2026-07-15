in ProofNamespace

+ Target
  -> argc1(value)
    value

+ ParentExactHolder
  -> new
    @receiver = Target.new()

  -> call(value)
    @receiver.argc1(value)

+ ReopenedChildHolder < ParentExactHolder
  -> replace(value)
    @receiver = value

# The canonical class AST is this last reopen and has no superclass field.
# The exact proof must retain the first declaration's inheritance edge.
+ ReopenedChildHolder
  -> child_call(value)
    @receiver.argc1(value)
