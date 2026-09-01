use core/optim

-> optim_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> optim_close?(left, right, tolerance = ~1.0e-8)
  (left - right).abs <= tolerance

linear_residual = -> (x)
  [x[0] - ~3.0, x[1] + ~2.0]

finite_difference = Optim.least_squares(
  linear_residual, [~0.0, ~0.0], 20)
optim_check("least_squares.fd.x",
            optim_close?(finite_difference[:x][0], ~3.0))
optim_check("least_squares.fd.y",
            optim_close?(finite_difference[:x][1], ~-2.0))
optim_check("least_squares.fd.objective",
            finite_difference[:fun] < ~1.0e-20)

identity_jacobian = -> (x)
  [[~1.0, ~0.0], [~0.0, ~1.0]]
analytic = Optim.least_squares(
  linear_residual, identity_jacobian,
  [~0.0, ~0.0], 20)
optim_check("least_squares.jacobian.x",
            optim_close?(analytic[:x][0], ~3.0))
optim_check("least_squares.jacobian.y",
            optim_close?(analytic[:x][1], ~-2.0))

rosenbrock_residual = -> (x)
  [~10.0 * (x[1] - x[0] * x[0]), ~1.0 - x[0]]
rosenbrock = Optim.least_squares(
  rosenbrock_residual, [~-1.2, ~1.0], 100)
optim_check("least_squares.nonlinear.x",
            optim_close?(rosenbrock[:x][0], ~1.0, ~1.0e-6))
optim_check("least_squares.nonlinear.y",
            optim_close?(rosenbrock[:x][1], ~1.0, ~1.0e-6))
optim_check("least_squares.nonlinear.objective",
            rosenbrock[:fun] < ~1.0e-16)

unchanged = Optim.least_squares(
  linear_residual, [~0.0, ~0.0], 0)
optim_check("least_squares.zero_iterations.x",
            unchanged[:x][0] == ~0.0)
optim_check("least_squares.zero_iterations.objective",
            optim_close?(unchanged[:fun], ~13.0))

<< "optim_spec: all checks passed"
