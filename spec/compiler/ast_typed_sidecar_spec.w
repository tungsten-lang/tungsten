use ../../compiler/lib/ast

-> check(name, got, expected)
  if got != expected
    << "FAIL [name]: got=[got] expected=[expected]"
    exit(1)

method = Tungsten:AST:MethodDef.new("work", [], [])
check("analysis absent", ast_analysis_get(method), nil)
analysis = {yield_block_name: "__block", needs_block_return: true}
method.lowering_analysis = analysis
check("analysis stored", ast_analysis_get(method), analysis)
check("analysis generic get", ast_get(method, :lowering_analysis), analysis)
analysis = {yield_block_name: nil, needs_block_return: false}
ast_set(method, :lowering_analysis, analysis)
check("analysis generic set", ast_analysis_get(method), analysis)

klass = Tungsten:AST:ClassDef.new("Box", nil, [], nil)
check("ivar offsets absent", ast_ivar_offsets_get(klass), nil)
check("ivar count absent", ast_ivar_count_get(klass), nil)
offsets = {"@value": 0, "@next": 1}
ast_ivar_offsets_set(klass, offsets)
ast_ivar_count_set(klass, 2)
check("ivar offsets stored", ast_ivar_offsets_get(klass), offsets)
check("ivar count stored", ast_ivar_count_get(klass), 2)
check("ivar offsets generic get", ast_get(klass, :ivar_offsets), offsets)
check("ivar count generic get", ast_get(klass, :ivar_count), 2)
ast_set(klass, :ivar_count, 3)
check("ivar count generic set", ast_ivar_count_get(klass), 3)

# Deep cloning copies typed and generic sparse metadata through the same
# ownership boundary.
method.recycle_safe = true
method.from_fn = true
method_clone = ast_deep_clone(method)
check("clone analysis", ast_analysis_get(method_clone), analysis)
check("clone generic", ast_get(method_clone, :recycle_safe), true)
check("materialized recycle getter", method.recycle_safe, true)
check("materialized from_fn getter", method.from_fn, true)
check("clone materialized from_fn getter", method_clone.from_fn, true)

klass_clone = ast_deep_clone(klass)
check("clone ivar offsets", ast_ivar_offsets_get(klass_clone), offsets)
check("clone ivar count", ast_ivar_count_get(klass_clone), 3)

<< "ast_typed_sidecar_spec: all checks passed"
