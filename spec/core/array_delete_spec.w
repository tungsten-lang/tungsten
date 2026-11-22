# Array#delete: Ruby's value delete (every equal element; returns the value, or nil when absent).
#
# Run: `bin/tungsten spec/core/array_delete_spec.w`

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

a = [1, 2, 3, 2, 4]
r = a.delete(2)
check("delete.all_equal", a, [1, 3, 4])
check("delete.returns_value", r, 2)
b = [1, 2]
check("delete.absent_nil", b.delete(9), nil)
check("delete.absent_unchanged", b, [1, 2])
c = ["x", "y", "x"]
c.delete("x")
check("delete.strings", c, ["y"])
d = [nil, 1, nil]
d.delete(nil)
check("delete.nil_values", d, [1])
o = [[1], [2]]
o.delete([1])
check("delete.by_equality", o, [[2]])
e = []
check("delete.empty", e.delete(1), nil)
f = [5, 5, 5]
f.delete(5)
check("delete.everything", f.size, 0)
<< "array_delete_spec: all passed"
