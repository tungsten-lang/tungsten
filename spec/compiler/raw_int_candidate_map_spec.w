# spec: compiled
# Focused regression coverage for raw_int_candidate_map's monotone
# fixed-point pruning.  The analyzer starts by assuming every untyped local
# assignment is machine-int-shaped, then repeatedly removes invalid candidates
# and anything that depended on them.

use ../../compiler/lib/ast
# The full lowering orchestrator (plus its error-formatter dependency),
# not individual workers: analysis.w references orchestrator-level
# symbols (infer_type, normalize_type_symbol, compile_error_for_node)
# through the flat namespace, so a worker-only use set fabricates
# dangling `__w_*` calls that die at link time (now a compile error).
use ../../compiler/lib/error_formatter
use ../../compiler/lib/lowering

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

# A resolved static call is int-shaped only when lowering will use a raw ABI
# and its declared return is an exact machine integer.
raw_static_mod = {
  known_static_methods: {
    "RawIntCandidateProbe.scan": {
      raw_abi: true,
      return_type: :i64,
      is_static: true
    }
  },
  known_classes: {"RawIntCandidateProbe": true},
  class_super_names: {},
  raw_callable_fns: {},
  fn_return_types: {}
}
raw_static_call = Tungsten:AST:Call.new(
  Tungsten:AST:ClassRef.new("RawIntCandidateProbe"),
  "scan",
  [Tungsten:AST:Var.new("seed")]
)
raw_static_chain = [
  Tungsten:AST:Assign.new(
    Tungsten:AST:Var.new("best"),
    Tungsten:AST:Int.new(65536)
  ),
  Tungsten:AST:Assign.new(
    Tungsten:AST:Var.new("next_position"),
    Tungsten:AST:BinaryOp.new(
      Tungsten:AST:Int.new(0),
      :MINUS,
      Tungsten:AST:Int.new(1)
    )
  ),
  Tungsten:AST:Assign.new(
    Tungsten:AST:Var.new("word"),
    Tungsten:AST:Int.new(0)
  ),
  Tungsten:AST:Assign.new(
    Tungsten:AST:Var.new("bit"),
    raw_static_call
  ),
  Tungsten:AST:Assign.new(
    Tungsten:AST:Var.new("position"),
    Tungsten:AST:BinaryOp.new(
      Tungsten:AST:BinaryOp.new(
        Tungsten:AST:Var.new("word"),
        :STAR,
        Tungsten:AST:Int.new(63)
      ),
      :PLUS,
      Tungsten:AST:Var.new("bit")
    )
  ),
  Tungsten:AST:Assign.new(
    Tungsten:AST:Var.new("best"),
    Tungsten:AST:Call.new(
      Tungsten:AST:Var.new("remaining"),
      "[]",
      [Tungsten:AST:Var.new("position")]
    )
  ),
  Tungsten:AST:Assign.new(
    Tungsten:AST:Var.new("next_position"),
    Tungsten:AST:Var.new("position")
  )
]
static_candidates = raw_int_candidate_map(
  raw_static_chain,
  {
    "remaining": :typed_array_u16,
    "seed": :u64
  },
  raw_static_mod
)
assert_candidate("raw static call bit", static_candidates, "bit")
assert_candidate("raw static call dependent position", static_candidates, "position")
assert_candidate("raw static call dependent best", static_candidates, "best")
assert_candidate("raw static call dependent result", static_candidates, "next_position")

inherited_static_mod = {
  known_static_methods: {
    "RawIntCandidateBase.scan": {
      raw_abi: true,
      return_type: :u64,
      is_static: true
    }
  },
  known_classes: {
    "RawIntCandidateBase": true,
    "RawIntCandidateChild": true
  },
  class_super_names: {
    "RawIntCandidateChild": "RawIntCandidateBase"
  },
  raw_callable_fns: {},
  fn_return_types: {}
}
inherited_static_assign = [
  Tungsten:AST:Assign.new(
    Tungsten:AST:Var.new("result"),
    Tungsten:AST:Call.new(
      Tungsten:AST:ClassRef.new("RawIntCandidateChild"),
      "scan",
      [Tungsten:AST:Var.new("seed")]
    )
  )
]
assert_candidate(
  "inherited raw static call",
  raw_int_candidate_map(inherited_static_assign, {"seed": :u64}, inherited_static_mod),
  "result"
)

blocked_static_assign = [
  Tungsten:AST:Assign.new(
    Tungsten:AST:Var.new("result"),
    Tungsten:AST:Call.new(
      Tungsten:AST:ClassRef.new("RawIntCandidateProbe"),
      "scan",
      [Tungsten:AST:Var.new("seed")],
      Tungsten:AST:Block.new([], [])
    )
  )
]
assert_empty(
  "attached block is not a raw static proof",
  raw_int_candidate_map(blocked_static_assign, {"seed": :u64}, raw_static_mod)
)

boxed_static_mod = {
  known_static_methods: {
    "RawIntCandidateProbe.scan": {
      raw_abi: false,
      return_type: :i64,
      is_static: true
    }
  },
  known_classes: {"RawIntCandidateProbe": true},
  class_super_names: {},
  raw_callable_fns: {},
  fn_return_types: {}
}
boxed_static_assign = [
  Tungsten:AST:Assign.new(
    Tungsten:AST:Var.new("result"),
    raw_static_call
  )
]
assert_empty(
  "boxed static call is not a raw proof",
  raw_int_candidate_map(boxed_static_assign, {"seed": :u64}, boxed_static_mod)
)

boxed_return_static_mod = {
  known_static_methods: {
    "RawIntCandidateProbe.scan": {
      raw_abi: true,
      return_type: :bool,
      is_static: true
    }
  },
  known_classes: {"RawIntCandidateProbe": true},
  class_super_names: {},
  raw_callable_fns: {},
  fn_return_types: {}
}
assert_empty(
  "boxed bool return is not a machine proof",
  raw_int_candidate_map(boxed_static_assign, {"seed": :u64}, boxed_return_static_mod)
)

raw_constructor_mod = {
  known_static_methods: {
    "RawIntCandidateProbe.new": {
      raw_abi: true,
      return_type: :i64,
      is_static: true
    }
  },
  known_classes: {"RawIntCandidateProbe": true},
  class_super_names: {},
  raw_callable_fns: {},
  fn_return_types: {}
}
raw_constructor_assign = [
  Tungsten:AST:Assign.new(
    Tungsten:AST:Var.new("result"),
    Tungsten:AST:Call.new(
      Tungsten:AST:ClassRef.new("RawIntCandidateProbe"),
      "new",
      [Tungsten:AST:Var.new("seed")]
    )
  )
]
assert_empty(
  "constructor needs pre-dispatch proof",
  raw_int_candidate_map(raw_constructor_assign, {"seed": :u64}, raw_constructor_mod)
)

instance_static_mod = {
  known_static_methods: {
    "RawIntCandidateProbe.scan": {
      raw_abi: true,
      return_type: :i64,
      is_static: false
    }
  },
  known_classes: {"RawIntCandidateProbe": true},
  class_super_names: {},
  raw_callable_fns: {},
  fn_return_types: {}
}
assert_empty(
  "typed instance entry is not a class static proof",
  raw_int_candidate_map(boxed_static_assign, {"seed": :u64}, instance_static_mod)
)

dynamic_static_call = Tungsten:AST:Call.new(
  Tungsten:AST:Var.new("probe"),
  "scan",
  [Tungsten:AST:Var.new("seed")]
)
dynamic_static_assign = [
  Tungsten:AST:Assign.new(
    Tungsten:AST:Var.new("result"),
    dynamic_static_call
  )
]
assert_empty(
  "dynamic receiver is not a static proof",
  raw_int_candidate_map(dynamic_static_assign, {"seed": :u64}, raw_static_mod)
)

raw_bare_mod = {
  known_static_methods: {},
  known_classes: {},
  class_super_names: {},
  raw_callable_fns: {"raw_scan": "__w_raw_scan"},
  fn_return_types: {"raw_scan": :i64}
}
raw_bare_assign = [
  Tungsten:AST:Assign.new(
    Tungsten:AST:Var.new("result"),
    Tungsten:AST:Call.new(
      nil,
      "raw_scan",
      [Tungsten:AST:Var.new("seed")]
    )
  )
]
assert_empty(
  "top-level call needs exact resolver proof",
  raw_int_candidate_map(raw_bare_assign, {"seed": :u64}, raw_bare_mod)
)

raw_scan_def = Tungsten:AST:MethodDef.new(
  "raw_scan",
  [Tungsten:AST:Param.new("seed")],
  [Tungsten:AST:Var.new("seed")]
)
proven_bare_mod = {
  known_static_methods: {},
  known_classes: {},
  class_super_names: {},
  raw_callable_fns: {"raw_scan": "__w_raw_scan"},
  fn_return_types: {"raw_scan": :i64},
  known_fn_defs: {"raw_scan": raw_scan_def},
  known_fn_param_counts: {"raw_scan": 1},
  known_fn_overloads: {}
}
assert_candidate(
  "proven top-level raw call promotes result",
  raw_int_candidate_map(raw_bare_assign, {"seed": :u64}, proven_bare_mod),
  "result"
)

# Tail-recursive contraction (`b.zero? ? a : gcd(b, a % b)`) is recognized as a
# non-expanding integer body when self_name is supplied, while arbitrary helper
# calls or multiple self-calls are rejected.
gcd_tail_body = [
  Tungsten:AST:If.new(
    Tungsten:AST:Call.new(Tungsten:AST:Var.new("b"), "zero?", []),
    [Tungsten:AST:Var.new("a")],
    [],
    [
      Tungsten:AST:Call.new(
        nil,
        "gcd_rec",
        [
          Tungsten:AST:Var.new("b"),
          Tungsten:AST:BinaryOp.new(
            Tungsten:AST:Var.new("a"),
            :PERCENT,
            Tungsten:AST:Var.new("b")
          )
        ]
      )
    ]
  )
]
gcd_params = [Tungsten:AST:Param.new("a"), Tungsten:AST:Param.new("b")]
if !body_is_non_expanding_int?(gcd_tail_body, gcd_params, "gcd_rec")
  << "FAIL tail-recursive gcd should be non-expanding int"
  exit(1)
<< "PASS tail-recursive gcd non-expanding int"

if body_is_non_expanding_int?(gcd_tail_body, gcd_params, "other_fn")
  << "FAIL non-self call in gcd body must be rejected"
  exit(1)
<< "PASS non-self call rejected in non-expanding int"

<< "PASS raw int candidate fixed point"
