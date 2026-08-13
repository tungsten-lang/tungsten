# Matrix#add_mut spec — in-place componentwise matrix addition.

m1 = Mat2<f64>.identity()
m2 = Mat2<f64>.identity()

m1.add_mut(m2)

-> expect(name, cond)
  if cond
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

expect("matrix.add_mut", m1.at(0, 0) == 2.0 && m1.at(1, 1) == 2.0)


