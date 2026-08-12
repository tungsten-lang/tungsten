# Tensor#add_mut spec — in-place mutate-if-unique tensor addition.

t1 = Tensor.zeros([2, 2])
t2 = Tensor.zeros([2, 2])

t1.add_mut(t2)

-> expect(name, cond)
  if cond
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

expect("tensor.add_mut", t1.at([0, 0]) == 0.0)

