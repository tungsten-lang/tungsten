# Decimal literals inside an array literal that crosses into a function, then
# each element converted to Float / absed. Exercises the literal -> boundary
# -> to_f/abs path in one shot.
-> to_floats(xs)
  xs.map -> (e) e.to_f

-> abs_all(xs)
  xs.map -> (e) e.abs

<< "array to_f: " + to_floats([0.1, 0.2, 0.3]).to_s
<< "array abs: " + abs_all([-0.1, 0.2, -0.3]).to_s
