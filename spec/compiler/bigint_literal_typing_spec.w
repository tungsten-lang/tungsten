# Beyond-i64 literals must infer :int (boxed), never a machine type: the
# machine arms would emit them as raw i64 immediates and LLVM wraps them.
# Pins the fix for `(0 - <big literal>) op ...` silently returning
# i64-wrapped results on the compiled engine (walker was always correct),
# including the result-type leg — a guarded op's outcome may be a BigInt,
# so an :int operand's result must stay :int for the ENCLOSING op.

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

# Inline negated big literals (leg 1: literal magnitude classification)
check("neg_add", (0 - 35337846926175710469148695631586043320799932111856858121700775344984629448299) + (0 - 40226240559017789668698413066465176199159659414403131968844850507462365945502), 0 - 75564087485193500137847108698051219519959591526259990090545625852446995393801)
check("neg_mul", (0 - 35337846926175710469148695631586043320799932111856858121700775344984629448299) * 3, 0 - 106013540778527131407446086894758129962399796335570574365102326034953888344897)
check("neg_and", (0 - 35337846926175710469148695631586043320799932111856858121700775344984629448299) & (0 - 40226240559017789668698413066465176199159659414403131968844850507462365945502), 0 - 42941009342805832525268654354132373214293071391447654219812726380844042428160)

# The result-type leg (leg 2): a guarded subtract's possibly-BigInt result
# must not feed a raw machine multiply.
check("neg_sub_mul", ((0 - 99999999999999999999999999999) - 1) * 2, 0 - 200000000000000000000000000000)

# Bare big literals in expressions
check("bare_big", 18446744073709551616 + 1, 18446744073709551617)

# Underscored spelling classifies identically
check("underscored", 18_446_744_073_709_551_616 + 0, 18446744073709551616)

# NOT covered here (open, machine-arm overflow on FITTING operands —
# `9223372036854775807 + 1` and `4611686018427387904 * 2` still wrap
# compiled while the walker promotes): fixing that requires the
# literal-typing/opt-in design decision recorded in the migration ledger.

<< "bigint_literal_typing_spec: all checks passed"
