# Regression coverage for the lowering function-name index. The top-level
# helper is appended after the index has seen the first class body, so the
# second reopen exercises index catch-up before replacing the earlier method.
# Only one function with the reopened method's symbol may survive, and the
# language's established last-definition-wins behavior must remain intact.

+ FunctionReplacementIndexProbe
  -> value
    1

-> function_replacement_index_between
  9

+ FunctionReplacementIndexProbe
  -> value
    2

probe = FunctionReplacementIndexProbe.new()
if probe.value() != 2
  << "FAIL function replacement index: reopened method did not win"
  exit(1)
if function_replacement_index_between() != 9
  << "FAIL function replacement index: intervening function was lost"
  exit(1)

<< "PASS function replacement index catch-up"
