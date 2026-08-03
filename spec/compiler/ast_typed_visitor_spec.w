use ../../compiler/lib/ast

-> check(name, got, expected)
  if got != expected
    << "FAIL [name]: got=[got] expected=[expected]"
    exit(1)

-> check_array(name, got, expected)
  check(name + " size", got.size(), expected.size())
  i = 0
  while i < expected.size()
    check(name + " item " + i.to_s(), got[i], expected[i])
    i += 1

-> visited(node)
  out = []
  ast_each_child(node) -> (child)
    out.push(ast_kind(child))
  out

left = Tungsten:AST:Int.new(1)
right = Tungsten:AST:Int.new(2)
binary = Tungsten:AST:BinaryOp.new(left, :+, right)

# The generated descriptor skips BinaryOp's scalar :op field while preserving
# the declared order of its two AST fields.
check_array("binary typed offsets", slab_child_offsets_table[KIND_BINARY_OP], [0, 2])
check_array("binary typed keys", slab_child_keys_table[KIND_BINARY_OP], [:left, :right])
check_array("binary visit", visited(binary), [:int, :int])

block = Tungsten:AST:Block.new([], [right])
call = Tungsten:AST:Call.new(binary, "f", [left], block, 11, 12)
check_array("call skips scalar fields", visited(call), [:binary_op, :int, :block])
check_array("compatibility collector", ast_children(call).map -> (child) ast_kind(child), [:binary_op, :int, :block])

# Hand-built Hash nodes remain supported by the generated key descriptor.
hash_binary = {node: :binary_op, left: left, op: :+, right: right}
check_array("hash fallback", visited(hash_binary), [:int, :int])

check("typed field descriptor", slab_field_type_for_id(KIND_BINARY_OP, :op), :w64)
check("typed field descriptor ast", slab_field_type_for_id(KIND_BINARY_OP, :left), :ast)

<< "PASS ast typed visitor"
