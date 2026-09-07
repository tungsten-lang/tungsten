# Optional GPU-emitter boundary for the compiler driver.
#
# The default image only needs to recognize whether a parsed program contains
# @gpu definitions. The full multi-dialect emitter is loaded by the thin Metal
# image and implements the same small object interface below.

use ast

+ CompilerGPUEmitter
  -> available?
    false

  -> contains_kernel?(node)
    if node == nil || !is_ast_node?(node)
      return false
    if ast_kind(node) == :gpu_kernel_def
      return true
    if ast_kind(node) == :program
      exprs = program_body(node)
      i = 0
      while i < exprs.size()
        if contains_kernel?(exprs[i])
          return true
        i += 1
      return false
    # A few compiler-only wrapper nodes (fastmath/strictmath/overflow) remain
    # hash-backed while ordinary syntax nodes use the packed AST slab. The
    # shared accessor handles both representations; dynamic `.body`/`.expressions`
    # dispatch would ask Object for those methods on the hash-backed nodes.
    body = ast_get(node, :body)
    if body != nil && type(body) == "Array"
      i = 0
      while i < body.size()
        if contains_kernel?(body[i])
          return true
        i += 1
    exprs = ast_get(node, :expressions)
    if exprs != nil && type(exprs) == "Array"
      i = 0
      while i < exprs.size()
        if contains_kernel?(exprs[i])
          return true
        i += 1
    false

  -> collect(ast)
    []

  -> emit_metal(kernels, only_index = nil)
    nil

  -> emit_cuda(kernels, only_index = nil)
    nil

  -> emit_wgsl(kernels, only_index = nil)
    nil
