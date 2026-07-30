# Numeric language constants must agree between the self-hosted interpreter
# and native lowering.  Symbolic algebra deliberately uses Expression.pi/e
# instead so exact identities survive evaluation.

-> check(label, actual, expected, tolerance = ~1.0e-14)
  if (actual - expected).abs > tolerance
    raise "[label]: expected [expected], got [actual]"

check("pi", π, ~3.141592653589793)
check("tau", τ, ~6.283185307179586)
check("phi", ϕ, ~1.618033988749895)
check("phi alias", φ, ϕ)
check("Euler number", ℯ, ~2.718281828459045)
check("Euler-Mascheroni", ℇ, ~0.5772156649015329)

<< "PASS numeric mathematical constants"
