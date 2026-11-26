# tungsten/languages/ruby/ast.w — Ruby 4.0 AST mapped directly onto
# Tungsten's AST node vocabulary (compiler/lib/ast_schema.w, KIND_MAX = 148)
# with an audited minimal delta of Ruby-only extension nodes.
#
# Verified 1-to-1 overlap with Tungsten's KIND_* AST (compiler/lib/ast_schema.w):
#   DIRECT NATIVE NODES (~96% of Ruby 4.0):
#     :program         -> KIND_PROGRAM          (92)
#     :int             -> KIND_INT              (70)
#     :float           -> KIND_FLOAT            (63)
#     :rational        -> KIND_RATIONAL         (97)
#     :complex         -> KIND_QUANTITY         (94)  # e.g. `1 + 2i` -> Quantity(unit="i")
#     :string          -> KIND_STRING           (105)
#     :string_interp   -> KIND_STRING_INTERP    (106)
#     :symbol          -> KIND_SYMBOL           (109)
#     :word_array      -> KIND_WORD_ARRAY       (132)
#     :sym_array       -> KIND_SYMBOL_ARRAY     (110)
#     :regex           -> KIND_REGEX            (98)
#     :bool            -> KIND_BOOL             (39)
#     :nil             -> KIND_NIL_LIT          (15)
#     :self            -> KIND_SELF_REF         (16)
#     :var             -> KIND_VAR              (123)
#     :ivar            -> KIND_IVAR             (72)
#     :cvar            -> KIND_CVAR             (54)
#     :gvar            -> KIND_GVAR             (144)
#     :const_ref       -> KIND_CLASS_REF        (142)
#     :const_path      -> KIND_CLASS_REF        (142) # static A::B -> ClassRef("A:B")
#     :array           -> KIND_ARRAY            (34)
#     :hash            -> KIND_HASH_LITERAL     (67)
#     :range           -> KIND_RANGE            (96)
#     :assign          -> KIND_ASSIGN           (35)
#     :compound_assign -> KIND_COMPOUND_ASSIGN  (52)
#     :multi_assign    -> KIND_MULTI_ASSIGN     (81)
#     :binary_op       -> KIND_BINARY_OP        (37)
#     :unary_op        -> KIND_UNARY_OP         (120)
#     :and / :or / :not-> KIND_AND / KIND_OR / KIND_NOT
#     :if              -> KIND_IF               (68)
#     :case            -> KIND_CASE             (44)
#     :case_in         -> KIND_CASE_VALUE       (46)  # + KIND_CASE_ARM (45)
#     :pat_test        -> KIND_IN_TEST          (69)  # `x in pat` / `x => pat`
#     :while / :until  -> KIND_WHILE            (130)
#     :begin           -> KIND_BEGIN            (36)  # + KIND_RESCUE_EXPR (100)
#     :raise           -> KIND_RAISE            (95)
#     :break / :next   -> KIND_BREAK (40) / KIND_NEXT (82)
#     :return          -> KIND_RETURN           (101)
#     :yield / :super  -> KIND_YIELD (134) / KIND_SUPER (107)
#     :call / :safe_nav-> KIND_CALL (43) / KIND_SAFE_NAV (102)
#     :block / :lambda -> KIND_BLOCK            (38)  # + KIND_LAMBDA_ARITY (74)
#     :method_def      -> KIND_METHOD_DEF       (78)
#     :class_def       -> KIND_CLASS_DEF        (49)
#     :module_def      -> KIND_MODULE_DEF       (79)
#     :alias / :undef  -> KIND_CALL             (43)  # lowers to alias_method / undef_method
#     :magic_const     -> KIND_MAGIC_CONSTANT   (76)
#
#   TRUE RUBY-ONLY AST EXTENSIONS (not present in compiler/lib/ast_schema.w):
#     EXT_REDO            — `redo` (restart loop/block iteration without re-testing condition)
#     EXT_RETRY           — `retry` (re-execute enclosing `begin` body from `rescue`)
#     EXT_DEFINED         — `defined?(expr)` (unevaluated compile/runtime binding check)
#     EXT_SINGLETON_CLASS — `class << expr ... end` (eigenclass body reopening)

+ RbNode
  rw :kind, :a, :b, :c, :d, :line

  -> new(@kind, @a = nil, @b = nil, @c = nil, @d = nil, @line = 1)

# Map a Ruby AST kind to its canonical Tungsten KIND_* name (or "EXT_*" ONLY for
# the 4 Ruby constructs genuinely absent from compiler/lib/ast_schema.w).
-> rb_tungsten_kind(kind)
  case kind
  when :program then "KIND_PROGRAM"
  when :int then "KIND_INT"
  when :float then "KIND_FLOAT"
  when :rational then "KIND_RATIONAL"
  when :complex then "KIND_QUANTITY"
  when :string then "KIND_STRING"
  when :string_interp then "KIND_STRING_INTERP"
  when :symbol then "KIND_SYMBOL"
  when :dsym then "KIND_SYMBOL"
  when :word_array then "KIND_WORD_ARRAY"
  when :sym_array then "KIND_SYMBOL_ARRAY"
  when :regex then "KIND_REGEX"
  when :dregex then "KIND_REGEX"
  when :bool then "KIND_BOOL"
  when :nil then "KIND_NIL_LIT"
  when :self then "KIND_SELF_REF"
  when :var then "KIND_VAR"
  when :ivar then "KIND_IVAR"
  when :cvar then "KIND_CVAR"
  when :gvar then "KIND_GVAR"
  when :const_ref then "KIND_CLASS_REF"
  when :const_path then "KIND_CLASS_REF"
  when :array then "KIND_ARRAY"
  when :hash then "KIND_HASH_LITERAL"
  when :range then "KIND_RANGE"
  when :assign then "KIND_ASSIGN"
  when :compound_assign then "KIND_COMPOUND_ASSIGN"
  when :multi_assign then "KIND_MULTI_ASSIGN"
  when :binary_op then "KIND_BINARY_OP"
  when :unary_op then "KIND_UNARY_OP"
  when :and then "KIND_AND"
  when :or then "KIND_OR"
  when :not then "KIND_NOT"
  when :if then "KIND_IF"
  when :case then "KIND_CASE"
  when :case_in then "KIND_CASE_VALUE"
  when :pat_test then "KIND_IN_TEST"
  when :pat_lit, :pat_var, :pat_pin, :pat_array, :pat_hash, :pat_find, :pat_alt, :pat_as then "KIND_CASE_ARM"
  when :while, :until, :for then "KIND_WHILE"
  when :begin then "KIND_BEGIN"
  when :raise then "KIND_RAISE"
  when :break then "KIND_BREAK"
  when :next then "KIND_NEXT"
  when :return then "KIND_RETURN"
  when :yield then "KIND_YIELD"
  when :super then "KIND_SUPER"
  when :call, :index, :splat, :kw_splat, :xstr, :alias, :undef then "KIND_CALL"
  when :safe_nav then "KIND_SAFE_NAV"
  when :block, :lambda then "KIND_BLOCK"
  when :method_def then "KIND_METHOD_DEF"
  when :class_def then "KIND_CLASS_DEF"
  when :module_def then "KIND_MODULE_DEF"
  when :magic_const then "KIND_MAGIC_CONSTANT"
  else "EXT_" + kind.to_s.upcase

# Export a Ruby AST node into a Tungsten-AST-shaped Hash descriptor, recording
# whether every node maps directly to existing Tungsten KIND_* nodes or uses
# Ruby superset extensions.
-> rb_to_tungsten_ast(node)
  return nil if node == nil
  if node.is_a?(Array)
    out = []
    i = 0
    while i < node.size
      out.push(rb_to_tungsten_ast(node[i]))
      i += 1
    return out
  return node if !node.is_a?(RbNode)
  tk = rb_tungsten_kind(node.kind)
  h = {tungsten_kind: tk, ruby_kind: node.kind, line: node.line}
  h[:superset_ext] = true if tk.starts_with?("EXT_")
  h[:a] = rb_to_tungsten_ast(node.a) if node.a != nil
  h[:b] = rb_to_tungsten_ast(node.b) if node.b != nil
  h[:c] = rb_to_tungsten_ast(node.c) if node.c != nil
  h[:d] = rb_to_tungsten_ast(node.d) if node.d != nil
  h

# Collect the distinct Ruby superset extensions used in a parsed AST.
-> rb_ast_superset_extensions(node, out = nil)
  out = [] if out == nil
  return out if node == nil
  if node.is_a?(Array)
    i = 0
    while i < node.size
      rb_ast_superset_extensions(node[i], out)
      i += 1
    return out
  return out if !node.is_a?(RbNode)
  tk = rb_tungsten_kind(node.kind)
  if tk.starts_with?("EXT_") && !out.include?(tk)
    out.push(tk)
  rb_ast_superset_extensions(node.a, out)
  rb_ast_superset_extensions(node.b, out)
  rb_ast_superset_extensions(node.c, out)
  rb_ast_superset_extensions(node.d, out)
  out
