# Focused regression coverage for raw_int_candidate_map's monotone
# fixed-point pruning.  The analyzer starts by assuming every untyped local
# assignment is machine-int-shaped, then repeatedly removes invalid candidates
# and anything that depended on them.

use ../../compiler/lib/ast
use ../../compiler/lib/lowering/types
use ../../compiler/lib/lowering/analysis

-> assert_empty(name, candidates)
  keys = candidates.keys()
  if keys.size() != 0
    << "FAIL " + name + ": expected no candidates, got " + keys.to_s()
    exit(1)
  << "PASS " + name

-> assert_candidate(name, candidates, key)
  if candidates[key] != true
    << "FAIL " + name + ": missing " + key
    exit(1)
  << "PASS " + name

# Candidate collection stops at nested definition boundaries.  This is the
# common fast path for main/class bodies containing declarations but no direct
# untyped assignment.
nested_body = [
  Tungsten:AST:MethodDef.new("nested", [], [
    Tungsten:AST:Assign.new(
      Tungsten:AST:Var.new("inside"),
      Tungsten:AST:Int.new(1)
    )
  ])
]
assert_empty("definition-only scope", raw_int_candidate_map(nested_body, {}))

# This chain needs three narrowing rounds: bad is removed first, then middle,
# then tail.  It guards the subset-cardinality convergence shortcut against
# stopping before dependent candidates have been invalidated.
invalidating_chain = [
  Tungsten:AST:Assign.new(
    Tungsten:AST:Var.new("bad"),
    Tungsten:AST:String.new("not an integer")
  ),
  Tungsten:AST:Assign.new(
    Tungsten:AST:Var.new("middle"),
    Tungsten:AST:BinaryOp.new(
      Tungsten:AST:Var.new("bad"),
      :PLUS,
      Tungsten:AST:Int.new(1)
    )
  ),
  Tungsten:AST:Assign.new(
    Tungsten:AST:Var.new("tail"),
    Tungsten:AST:BinaryOp.new(
      Tungsten:AST:Var.new("middle"),
      :PLUS,
      Tungsten:AST:Int.new(1)
    )
  )
]
assert_empty("transitive invalidation", raw_int_candidate_map(invalidating_chain, {}))

# A mutually dependent integer-shaped cycle is a stable greatest fixed point,
# so equal cardinality must retain both candidates.
stable_cycle = [
  Tungsten:AST:Assign.new(
    Tungsten:AST:Var.new("left"),
    Tungsten:AST:BinaryOp.new(
      Tungsten:AST:Var.new("right"),
      :PLUS,
      Tungsten:AST:Int.new(1)
    )
  ),
  Tungsten:AST:Assign.new(
    Tungsten:AST:Var.new("right"),
    Tungsten:AST:BinaryOp.new(
      Tungsten:AST:Var.new("left"),
      :MINUS,
      Tungsten:AST:Int.new(1)
    )
  )
]
cycle_candidates = raw_int_candidate_map(stable_cycle, {})
if cycle_candidates.keys().size() != 2
  << "FAIL stable dependency cycle: expected 2 candidates"
  exit(1)
assert_candidate("stable dependency cycle left", cycle_candidates, "left")
assert_candidate("stable dependency cycle right", cycle_candidates, "right")

<< "PASS raw int candidate fixed point"
