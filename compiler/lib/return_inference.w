# Return type inference — Phase 3 of the compiler/language-improvements plan.
#
# When a method or fn is defined without an explicit return type annotation
# (the `-> add(a, b) i64 : a + b` form), infer one from the body so downstream
# code can use type-directed optimizations and gradual-typing diagnostics.
#
# Phase 3 MVP ships one inference rule: accumulator-seed inference.
# When a method uses the accumulator form — where a trailing expression after
# the param list becomes the seed for an indented body that mutates it — the
# seed's static type IS the return type. The parser desugars this form at
# parser.w:1360-1368: the trailing expression becomes `acc_name = trailing_expr`
# at the head of the body, and the final body statement is `Tungsten:AST:Var.new(acc_name)`.
# By the time this inference runs on the AST, that desugaring has happened.
#
# The accumulator-seed rule is always-terminating: no call-graph walk, no
# fixed-point iteration, no SCC detection. Just look at the first statement
# of the body, see if it's `acc = seed` where the final return is `Var(acc)`,
# and use infer_type(seed) as the return type.
#
# The fixed-point SCC pass for recursive methods is deferred to Phase 3b.
# For that pass, topologically sort the call graph, handle leaf nodes first
# with a single forward pass, iterate on mutually-recursive groups until the
# types converge or a max-iterations guard fires with a warning.

use ast
use runtime_types

# Try to infer a return type from an accumulator-form method body.
#
# Returns a type symbol (e.g. :int, :float, :string) if the body matches
# the accumulator shape and the seed has an inferrable type. Returns nil
# if the body doesn't match the shape or the seed's type can't be determined.
#
# Shape recognition: the parser desugars `-> sum(items) 0 \n items -> out += i`
# into a body that starts with `acc = 0` and ends with `Tungsten:AST:Var.new(acc)`. We
# detect this by checking that the first statement is an assign of a literal
# or an inferrable expression, and the last statement is a var reference
# to the assignment's target.
-> infer_accumulator_return_type(body, var_types, fn_return_types, infer_maps)
  if body == nil || body.size() < 2
    return nil
  first = body[0]
  last = body[body.size() - 1]
  if first == nil || last == nil
    return nil
  if ast_kind(first) != :assign
    return nil
  if ast_kind(last) != :var
    return nil
  target = first.target
  if target == nil || ast_kind(target) != :var
    return nil
  if target.name != last.name
    return nil
  # Found the accumulator shape — infer from the seed value.
  infer_type(first.value, var_types, fn_return_types, infer_maps)

# Top-level entry: given a method/fn AST node, return its inferred return
# type or nil if no inference rule matches. Called from lower_method_def /
# lower_fn_def when the node has no explicit :return_type annotation.
-> infer_return_type(node, var_types, fn_return_types, infer_maps)
  # Explicit annotation wins — caller should check this first but we
  # defensively honor it here too.
  if node.return_type != nil
    return node.return_type
  # Accumulator-seed rule
  acc_type = infer_accumulator_return_type(node.body, var_types, fn_return_types, infer_maps)
  if acc_type != nil
    return acc_type
  # Fall through to the existing last-expression inference (Phase 3 does
  # not add new machinery here — just uses whatever infer_fn_return_type
  # already does).
  infer_fn_return_type(node, infer_maps)
