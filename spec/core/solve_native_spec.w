# Minimal dual-engine regression for the Solve parameter/LLVM-name boundary.
#
#   bin/tungsten run spec/core/solve_native_spec.w
#   bin/tungsten compile spec/core/solve_native_spec.w \
#     --out /tmp/solve-native-spec

use core/solve

decay = -> (time, state)
  [~0.0 - state[0]]

trajectory = Solve.rk4(decay, ~0.0, ~1.0, [~1.0], ~0.05)
states = trajectory[:y]
final_value = states[states.size - 1][0]
difference = final_value - ~0.36787944117144233
difference = ~0.0 - difference if difference < ~0.0
raise "FAIL solve.native.rk4" if difference > ~3.0e-8
<< "PASS solve.native.rk4"
