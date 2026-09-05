use calculus
use optim

-> improved_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> improved_close?(value, expected, tolerance = ~1.0e-8)
  (value - expected).abs <= tolerance

-> improved_raises(name, action)
  raised = []
  begin
    action(~0.0)
  rescue error
    raised.push(true)
  improved_check(name, raised.size == 1)

# Geometry errors persist even after subtracting the large common offset.
h = ~1.0835776720341527e-14
resonance = Calculus.numerical_derivative(-> (x) x - ~1.0, ~1.0, 1, :central, h)
improved_check("difference.geometry.no_false_convergence", !resonance.converged?)
improved_check("difference.geometry.floor", resonance.resolution_floor > ~1.0e-3)
resonance2 = Calculus.numerical_derivative(
  -> (x) (x-~1.0)*(x-~1.0), ~1.0, 2, :central, h)
improved_check("difference.geometry.second", !resonance2.converged?)
quantized = Calculus.numerical_derivative(
  -> (x) x*x, ~1.0, 2, :central, ~8.548717289613706e-16)
improved_check("difference.quantized_samples", !quantized.converged? && quantized.error_estimate > ~1.0)
forward_resonance = Calculus.numerical_derivative(
  -> (x) x-~1.0, ~1.0, 1, :forward, ~1.0824674490095276e-14)
backward_resonance = Calculus.numerical_derivative(
  -> (x) x-~1.0, ~1.0, 1, :backward, ~5.412337245047638e-15)
improved_check("difference.geometry.one_sided", !forward_resonance.converged? && !backward_resonance.converged?)
forwards = Calculus.numerical_derivative(-> (x) x*x*x, ~1.0, 1, :forward)
backwards = Calculus.numerical_derivative(-> (x) x*x*x, ~1.0, 1, :backward)
second_forward = Calculus.numerical_derivative(-> (x) x*x*x*x, ~1.0, 2, :forward)
improved_check("difference.one_sided.nonzero", forwards.converged? && backwards.converged? && second_forward.converged?)
improved_check("difference.one_sided.scale", improved_close?(forwards.value, ~3.0) && improved_close?(backwards.value, ~3.0) && improved_close?(second_forward.value, ~12.0))
improved_check("difference.center_cached", forwards.evaluations == 1 + 2*forwards.levels && second_forward.evaluations == 1 + 3*second_forward.levels)
extreme = Calculus.numerical_stencil(-> (x) ~0.0, ~-1.0e308, ~9.0e307, 2, :forward)
improved_check("difference.affine_fma", extreme[2] == :ok)
small_log = Calculus.numerical_derivative(-> (x) Math.log(x), ~1.0e-6)
improved_check("difference.small_domain", small_log.converged? && improved_close?(small_log.value, ~1.0e6, ~0.01))
stale = Calculus.numerical_derivative(
  -> (x) x.abs < ~0.06 ? ~2.0*x : x, ~0.0, 1, :central, ~0.1, ~1.0e-10, ~1.0e-8, 3)
improved_check("difference.stale_error_visible", !stale.converged? && stale.error_estimate > ~1.0)
large = Calculus.numerical_derivative(
  -> (x) ~1.0e308*x, ~0.0, 1, :central, nil, ~1.0e-10, ~2.0)
improved_check("difference.tolerance_overflow", large.converged?)
improved_raises("difference.invalid_abs_tol", -> (unused)
  Calculus.numerical_derivative(-> (x) x, ~0.0, 1, :central, nil, ~0.0))
improved_raises("difference.result_invariant", -> (unused)
  NumericalDerivativeResult.new(nil, nil, nil, 0, 0, 1, :central, :converged, nil, false))

huge_integral = Calculus.integrate_gk15(-> (x) ~1.0e308, ~0.0, ~1.0, ~1.0e-10, ~2.0)
improved_check("gk.tolerance_overflow", huge_integral.converged?)
typed = Calculus.integrate_gk15(-> (x) 1, ~0.0, ~1.0)
improved_check("gk.wrong_type", typed.status == :unsupported_sample_type)
piecewise = -> (x) x < ~0.2 ? ~-2.0 : ~3.0
split = Calculus.integrate_with_points(piecewise, ~0.0, ~1.0, [~0.2])
reverse = Calculus.integrate_with_points(piecewise, ~1.0, ~0.0, [~0.2])
improved_check("gk.breakpoints.value", split.converged? && improved_close?(split.value, ~2.0))
improved_check("gk.breakpoints.reverse", reverse.converged? && improved_close?(reverse.value, ~-2.0))
improved_check("gk.breakpoints.counts", split.intervals == 2 && split.evaluations == 30)
improved_raises("gk.breakpoints.duplicates", -> (unused) Calculus.integrate_with_points(piecewise, ~0.0, ~1.0, [~0.2, ~0.2]))
improved_raises("gk.breakpoints.budget", -> (unused) Calculus.integrate_with_points(piecewise, ~0.0, ~1.0, [~0.2], ~1.0e-10, ~0.0, 1))
failure_callback = -> (x)
  x == ~0.25 ? Math.log(~-1.0) : (x-~0.123456789).abs
failure = Calculus.integrate_gk15(failure_callback, ~0.0, ~1.0, ~1.0e-16, ~0.0)
improved_check("gk.child.fail_fast", failure.status == :nonfinite_integrand && failure.evaluations == 16)
improved_check("gk.child.failure_text", failure.to_s.include?("nonfinite_integrand"))
heap_panels = [[~0.0, ~1.0, ~0.0, ~0.0, ~1.0]]
heap = [0]
trace_same = true
iteration = 0
while iteration < 200
  expected = Calculus.gk15_largest_error_index(heap_panels)
  trace_same = false if heap[0] != expected
  slot = heap[0]
  # Include ties and increases as well as decreasing child errors.
  heap_panels[slot] = [~0.0, ~1.0, ~0.0, ~0.0, (iteration % 7) + ~0.0]
  heap_panels.push([~0.0, ~1.0, ~0.0, ~0.0, (iteration % 5) + ~0.0])
  Calculus.gk15_heap_down(heap, heap_panels)
  Calculus.gk15_heap_push(heap, heap_panels, heap_panels.size - 1)
  iteration += 1
improved_check("gk.heap.stable_scan_parity", trace_same)
improved_raises("quadrature.result_invariant", -> (unused)
  QuadratureResult.new(nil, nil, 0, 0, false, :converged, :adaptive_gk15, :embedded_gauss_kronrod, nil, nil, nil, nil, false, false))
improved_raises("simpson.nan_bound", -> (unused) Calculus.integrate(-> (x) x, Math.log(~-1.0), ~1.0))
improved_raises("simpson.inf_tolerance", -> (unused) Calculus.integrate(-> (x) x, ~0.0, ~1.0, Math.exp(~1000.0)))
invalid_simpson = Calculus.integrate(-> (x) Math.log(~-1.0), ~0.0, ~1.0)
improved_check("simpson.nonfinite_no_estimate", invalid_simpson.status == :nonfinite_integrand && !invalid_simpson.estimate_available?)
simpson_child = Calculus.integrate(failure_callback, ~0.0, ~1.0)
improved_check("simpson.child_failure", simpson_child.status == :nonfinite_integrand && simpson_child.estimate_available?)

improved_raises("ad.scalar_rejects_vector", -> (unused) Calculus.gradient(-> (v) [v[0], v[1]], [~1.0, ~2.0]))
improved_raises("ad.jet_rejects_vector", -> (unused) Calculus.derivative(-> (x) [x], ~1.0))
captured = Differential.variable(~1.0, 1, 0)
improved_raises("ad.dimension", -> (unused) Calculus.gradient(-> (v) captured, [~1.0, ~2.0]))
captured_jet = TaylorJet.variable(~1.0, 1)
improved_raises("ad.order", -> (unused) Calculus.derivative(-> (x) captured_jet, ~1.0, 3))
improved_raises("ad.jacobian_ragged", -> (unused) Calculus.jacobian(-> (v) [captured, v[1]], [~1.0, ~2.0]))
improved_raises("ad.log_domain", -> (unused) Calculus.gradient(-> (v) v[0].log, [~-1.0]))
improved_raises("ad.atanh_domain", -> (unused) Calculus.derivative(-> (x) x.atanh, ~2.0))
improved_raises("ad.acosh_domain", -> (unused) Calculus.gradient(-> (v) v[0].acosh, [~-2.0]))
improved_raises("ad.sqrt_domain", -> (unused) Calculus.derivative(-> (x) x.sqrt, ~-1.0))
improved_raises("ad.nan_point", -> (unused) Calculus.gradient(-> (v) v[0], [Math.log(~-1.0)]))
sum = Differential.variable(~2.0, 2, 0) + Differential.variable(~3.0, 2, 1)
improved_check("ad.add", sum.value == ~5.0 && sum.gradient == [~1.0, ~1.0] && sum.hessian == [[~0.0, ~0.0], [~0.0, ~0.0]])
improved_check("ad.negative_integer_power", Calculus.gradient(-> (v) v[0]**2, [~-2.0]) == [~-4.0])
improved_check("ad.zero_power_at_zero", Calculus.hessian(-> (v) v[0]**0, [~0.0]) == [[~0.0]])
improved_check("ad.identity_power_at_zero", Calculus.hessian(-> (v) v[0]**1, [~0.0]) == [[~0.0]])

scalar = -> (v) v[0]*v[1] + v[0]*v[0]
ng = Calculus.numerical_gradient(scalar, [~2.0, ~3.0])
improved_check("numerical_gradient.values", ng.converged? && improved_close?(ng.value[0], ~7.0) && improved_close?(ng.value[1], ~2.0))
improved_check("numerical_gradient.metadata", ng.rank == 1 && !ng.certified? && ng.component_results.size == 2)
vector = -> (v) [v[0]*v[1], v[0]*v[0]]
nj = Calculus.numerical_jacobian(vector, [~2.0, ~3.0])
improved_check("numerical_jacobian.values", nj.converged? && improved_close?(nj.value[0][0], ~3.0) && improved_close?(nj.value[1][0], ~4.0) && improved_close?(nj.value[1][1], ~0.0))
improved_check("numerical_jacobian.shared_samples", nj.evaluations == 13)
improved_check("numerical_gradient.empty", Calculus.numerical_gradient(-> (v) ~7.0, []).value == [])
improved_check("numerical_jacobian.empty", Calculus.numerical_jacobian(-> (v) [~7.0], []).value == [[]])
improved_raises("numerical_gradient.empty_options", -> (unused) Calculus.numerical_gradient(-> (v) ~7.0, [], :invalid))
improved_raises("numerical_jacobian.empty_options", -> (unused) Calculus.numerical_jacobian(-> (v) [], [~1.0], :central, ~0.0))
gradient_failure = Calculus.numerical_gradient(-> (v) Math.log(~-1.0), [~1.0])
improved_check("numerical_gradient.failure", !gradient_failure.estimate_available? && gradient_failure.value == nil && gradient_failure.status == :nonfinite_sample)
improved_raises("numerical_jacobian.shape", -> (unused) Calculus.numerical_jacobian(-> (v) v[0] > ~1.0 ? [v[0]] : [v[0], v[0]], [~1.0]))
optim_result = Optim.fd_grad_result(scalar, [~2.0, ~3.0])
improved_check("optim.status_adapter", optim_result.converged?)
improved_raises("optim.failure_is_loud", -> (unused) Optim.fd_grad(-> (v) Math.log(~-1.0), [~1.0]))

jvp = Calculus.jvp(vector, [~2.0, ~3.0], [~1.0, ~2.0])
vjp = Calculus.vjp(vector, [~2.0, ~3.0], [~1.0, ~2.0])
improved_check("autodiff.jvp", jvp["jvp"] == [~7.0, ~4.0])
improved_check("autodiff.vjp", vjp["vjp"] == [~11.0, ~2.0])
improved_check("autodiff.transpose_identity", jvp["jvp"][0] + ~2.0*jvp["jvp"][1] == vjp["vjp"][0] + ~2.0*vjp["vjp"][1])
reverse_gradient = Calculus.reverse_gradient(scalar, [~2.0, ~3.0])
improved_check("autodiff.reverse_gradient", reverse_gradient == [~7.0, ~2.0])
unused_overflow = -> (v)
  ignored = v[0].exp
  v[0] + ~0.0
improved_check("autodiff.unused_overflow", Calculus.reverse_gradient(unused_overflow, [~1000.0]) == [~1.0])
improved_raises("autodiff.reachable_overflow", -> (unused) Calculus.reverse_gradient(-> (v) v[0].exp.tanh, [~1000.0]))
improved_raises("autodiff.cotangent_shape", -> (unused) Calculus.vjp(vector, [~2.0, ~3.0], [~1.0]))
improved_raises("autodiff.jvp_shape", -> (unused) Calculus.jvp(vector, [~2.0, ~3.0], [~1.0]))
improved_check("autodiff.constant", Calculus.reverse_gradient(-> (v) ~7.0, [~2.0]) == [~0.0])
improved_raises("autodiff.log_domain", -> (unused) Calculus.jvp(-> (v) v[0].log, [~-1.0], [~1.0]))
improved_raises("autodiff.invalid_tape_index", -> (unused) TapeValue.new(Tape.new, 0))
primitive_mix = -> (v)
  x = v[0]
  y = v[1]
  x.sin + y.cos + (x*y).tanh + x.exp + y.log + x.sqrt + x**3 / y - x.scale(~2.0)
mix_point = [~1.2, ~0.7]
mix_gradient = Calculus.gradient(primitive_mix, mix_point)
mix_reverse = Calculus.reverse_gradient(primitive_mix, mix_point)
mix_forward = Calculus.jvp(primitive_mix, mix_point, [~0.3, ~-0.4])
improved_check("autodiff.primitives.reverse", improved_close?(mix_reverse[0], mix_gradient[0]) && improved_close?(mix_reverse[1], mix_gradient[1]))
improved_check("autodiff.primitives.forward", improved_close?(mix_forward["jvp"], ~0.3*mix_gradient[0] - ~0.4*mix_gradient[1]))
improved_check("autodiff.repeated_outputs", Calculus.vjp(-> (v) [v[0], v[0], ~2.0], [~1.0], [~2.0, ~-1.0, ~7.0])["vjp"] == [~1.0])
improved_check("autodiff.scalar_jvp_constant", Calculus.jvp(-> (v) ~7.0, [~1.0], [~0.0])["jvp"] == ~0.0)
improved_raises("autodiff.zero_seed_still_validates", -> (unused) Calculus.vjp(-> (v) v[0].exp.tanh, [~1000.0], ~0.0))

<< "calculus_improvements_spec: all checks passed"
