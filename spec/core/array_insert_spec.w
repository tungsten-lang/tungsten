# Array#insert: Ruby's single-value insert (before idx, negative from the end, nil padding past the end).
#
# Run: `bin/tungsten spec/core/array_insert_spec.w`

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

a = [1, 2, 3]
r = a.insert(1, 9)
check("insert.middle", a, [1, 9, 2, 3])
check("insert.returns_self", r.size, 4)
check("insert.front", [2, 3].insert(0, 1), [1, 2, 3])
check("insert.end", [1, 2].insert(2, 3), [1, 2, 3])
check("insert.neg1_appends", [1, 2].insert(-1, 7), [1, 2, 7])
check("insert.neg2", [1, 2, 3].insert(-2, 8), [1, 2, 8, 3])
check("insert.pad", [1].insert(3, 4), [1, nil, nil, 4])
check("insert.empty", [].insert(0, "x"), ["x"])
dyn = []
dyn.insert(0, ["b", "2"])
dyn.insert(0, ["a", "1"])
check("insert.nested_first", dyn[0], ["a", "1"])
check("insert.nested_size", dyn.size, 2)
raised = false
begin
  [1, 2].insert(-4, 0)
rescue e
  raised = true
check("insert.too_small_raises", raised, true)
