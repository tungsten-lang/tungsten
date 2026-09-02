# Regression: a local read under a machine-int type ascription in argument
# position (`f(x ## u64)`) is a VALUE use, not a storage escape, so it must
# stay a raw-int promotion candidate.
#
# Before the fix, visit_promote_node had no :type_ascription arm and the
# ascription fell into the conservative bulk-escape branch.  Once the
# raw-typed assignment arm honored the candidate gate, such a local became a
# boxed WValue slot; a 63-bit word then boxed into a heap BigInt, and the
# `x & (x - 1)` bit walk of the LRC(13) sieve's MRV selector paid a BigInt
# allocation per step (3000x slower than the August 11 compiler on p607).

use ../../compiler/lib/ast
use ../../compiler/lib/error_formatter
use ../../compiler/lib/lowering

-> assert_candidate(name, candidates, key)
  if candidates[key] != true
    << "FAIL " + name + ": missing " + key
    exit(1)
  << "PASS " + name

-> assert_not_candidate(name, candidates, key)
  if candidates[key] == true
    << "FAIL " + name + ": unexpected candidate " + key
    exit(1)
  << "PASS " + name

bitops_mod = {
  known_static_methods: {
    "BitOps.trailing_zeros_u64": {
      raw_abi: true,
      return_type: :i64,
      is_static: true
    }
  },
  known_classes: {"BitOps": true},
  class_super_names: {},
  raw_callable_fns: {},
  fn_return_types: {}
}

# The exact shape of lrc_v4_next_to_cover's inner loop:
#
#   missing_word = goal[word] ^ covered[covered_offset + word]
#   while missing_word != 0
#     bit = BitOps.trailing_zeros_u64(missing_word ## u64) ## i64
#     missing_word = missing_word & (missing_word - 1)
mrv_body = [
  Tungsten:AST:Assign.new(
    Tungsten:AST:Var.new("missing_word"),
    Tungsten:AST:BinaryOp.new(
      Tungsten:AST:Call.new(Tungsten:AST:Var.new("goal"), "[]", [Tungsten:AST:Var.new("word")]),
      :CARET,
      Tungsten:AST:Call.new(
        Tungsten:AST:Var.new("covered"),
        "[]",
        [Tungsten:AST:BinaryOp.new(Tungsten:AST:Var.new("covered_offset"), :PLUS, Tungsten:AST:Var.new("word"))]
      )
    )
  ),
  Tungsten:AST:While.new(
    Tungsten:AST:BinaryOp.new(Tungsten:AST:Var.new("missing_word"), :NEQ, Tungsten:AST:Int.new(0)),
    [
      Tungsten:AST:Assign.new(
        Tungsten:AST:Var.new("bit"),
        Tungsten:AST:Call.new(
          Tungsten:AST:ClassRef.new("BitOps"),
          "trailing_zeros_u64",
          [Tungsten:AST:TypeAscription.new(Tungsten:AST:Var.new("missing_word"), "u64")]
        ),
        "i64"
      ),
      Tungsten:AST:Assign.new(
        Tungsten:AST:Var.new("missing_word"),
        Tungsten:AST:BinaryOp.new(
          Tungsten:AST:Var.new("missing_word"),
          :AMPERSAND,
          Tungsten:AST:BinaryOp.new(Tungsten:AST:Var.new("missing_word"), :MINUS, Tungsten:AST:Int.new(1))
        )
      )
    ]
  )
]
mrv_candidates = raw_int_candidate_map(
  mrv_body,
  {
    "goal": :typed_array_i64,
    "covered": :typed_array_i64,
    "covered_offset": :i64,
    "word": :i64
  },
  bitops_mod
)
assert_candidate("ascribed call argument keeps the local a raw candidate", mrv_candidates, "missing_word")

# Control: the same local passed to a plain ccall still escapes (calls.w's
# raw-argument ABI contract), ascription or not.
ccall_body = [
  Tungsten:AST:Assign.new(
    Tungsten:AST:Var.new("word_bits"),
    Tungsten:AST:BinaryOp.new(
      Tungsten:AST:Call.new(Tungsten:AST:Var.new("goal"), "[]", [Tungsten:AST:Var.new("word")]),
      :CARET,
      Tungsten:AST:Call.new(Tungsten:AST:Var.new("covered"), "[]", [Tungsten:AST:Var.new("word")])
    )
  ),
  Tungsten:AST:Assign.new(
    Tungsten:AST:Var.new("sink"),
    Tungsten:AST:Call.new(
      nil,
      "ccall",
      [Tungsten:AST:String.new("w_int"), Tungsten:AST:Var.new("word_bits")]
    )
  )
]
ccall_candidates = raw_int_candidate_map(
  ccall_body,
  {"goal": :typed_array_i64, "covered": :typed_array_i64, "word": :i64},
  bitops_mod
)
assert_not_candidate("plain ccall argument still pins the local", ccall_candidates, "word_bits")

<< "raw_int_candidate_ascription_spec: all checks passed"
