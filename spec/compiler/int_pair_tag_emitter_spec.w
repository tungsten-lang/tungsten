use ../../compiler/lib/emitter

-> check(name, ok)
  if ok
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

-> check_pair_helper(name, ir)
  check(name + ".tag_shift_a", ir.include?("%ta = lshr i64 %a, 48"))
  check(name + ".tag_shift_b", ir.include?("%tb = lshr i64 %b, 48"))
  check(name + ".int_tag_a", ir.include?("%ia = icmp eq i64 %ta, 65530"))
  check(name + ".int_tag_b", ir.include?("%ib = icmp eq i64 %tb, 65530"))
  check(name + ".both", ir.include?("%both = and i1 %ia, %ib"))

check_pair_helper("compare", cmp_fast_helper_ir("__test_cmp", "w_eq", "eq", false))
check_pair_helper("arithmetic", arith_fast_helper_ir("__test_add", "w_add", "add"))
check_pair_helper("bitwise", bitop_fast_helper_ir("__test_and", "w_bit_and", "and"))
check_pair_helper("multiply", mul_fast_helper_ir())
check_pair_helper("division", divmod_fast_helper_ir("__test_div", "w_div", "sdiv"))
check_pair_helper("shift", shift_fast_helper_ir("__test_shl", "w_bit_shl", true))

big_ir = bigint_zero_cmp_fast_helper_ir("__test_big_zero", "w_eq", "eq")
check("bigint.current_tag", big_ir.include?("%isbig = icmp eq i64 %t, 65531"))
check("bigint.no_instant_tag", !big_ir.include?("%isbig = icmp eq i64 %t, 65528"))
