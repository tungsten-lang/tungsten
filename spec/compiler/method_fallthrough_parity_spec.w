# A final conditional is an expression only along the arm that actually runs.
# A method path that reaches the end without producing a value returns nil.

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got=" + got.to_s() + " want=" + want.to_s()
    exit 1

-> final_if(flag)
  if flag
    7

-> final_elsif(value)
  if value == 1
    11
  elsif value == 2
    22

-> explicit_return_or_fallthrough(flag)
  if flag
    return 31

-> nested_final_if(outer, inner)
  if outer
    if inner
      41

check("final_if.taken_value", final_if(true), 7)
check("final_if.untaken_nil", final_if(false), nil)
check("final_elsif.first_value", final_elsif(1), 11)
check("final_elsif.second_value", final_elsif(2), 22)
check("final_elsif.no_arm_nil", final_elsif(3), nil)
check("explicit_return.taken", explicit_return_or_fallthrough(true), 31)
check("explicit_return.fallthrough_nil", explicit_return_or_fallthrough(false), nil)
check("nested_if.taken_value", nested_final_if(true, true), 41)
check("nested_if.inner_untaken_nil", nested_final_if(true, false), nil)
check("nested_if.outer_untaken_nil", nested_final_if(false, true), nil)
