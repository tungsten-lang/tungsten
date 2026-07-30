# Symbolic expressions

`Expression` is Tungsten's canonical symbolic real-expression tree. It is
autoloaded directly, and `use calculus` adds the shorter
`Calculus.symbol` / `Calculus.symbols` constructors.

```w
use calculus

x, y = Calculus.symbols([:x, :y])
f = x**3*y + (x*y).sin + x.log1p

f
f.derivative(:x)
f.gradient([:x, :y])
f.hessian([:x, :y])
f.free_variables
```

Construction simplifies immediately. Addition and multiplication are
flattened and sorted, exact constants are combined, like terms and repeated
factors are collected, neutral elements disappear, and safe real identities
such as `log(exp(x)) = x` and `sqrt(x²) = abs(x)` are applied. Variables are
real unless a future assumptions layer says otherwise.

The elementary surface matches numeric calculus:

```text
exp log sqrt sin cos tan sinh cosh tanh
asin acos atan asinh acosh atanh
expm1 log1p log2 log10 cbrt abs
```

## Substitution and evaluation

`substitute` returns another simplified expression. `evaluate` accepts String
or Symbol keys and returns values in the supplied domain:

```w
g = f.substitute({y: x + 1})
g.evaluate({x: ~0.5})

jet = TaylorJet.variable(~0.5, 5)
f.evaluate({x: jet, y: ~2.0})

z = Complex<f64>.new([~0.5, ~0.25])
f.evaluate({x: z, y: ~2.0})
```

The same evaluation path works with `Differential` and exact `Polynomial`
values. This lets one formula serve symbolic manipulation, arbitrary-order
Taylor differentiation, gradients/Hessians, complex analysis, and exact
polynomial evaluation.

## Exact polynomial bridge

```w
use algebra

ring = PolynomialRing.new([:x, :y], RationalField.new)
p = (x**3 * Rational.new(1, 2) + x*y*3 - y).to_polynomial(ring)
expression = p.to_expression
```

`to_polynomial` rejects transcendental operations, nonconstant denominators,
negative/nonintegral exponents, and variables missing from the target ring.
`Polynomial#to_expression` currently accepts rational-field polynomials.
Finite-field and number-field coefficients need field-aware symbolic constants
before that reverse conversion can preserve their representation, so it fails
loudly today.

## Current boundary

This is a simplifier and exact differentiator, not yet a complete computer
algebra system. It does not currently provide symbolic integration, equation
solving, assumptions/refinement, piecewise expressions, limits, series at
singularities, or general factor/expand/collect commands. Polynomial-native
factorization, Gröbner bases, ideals, and geometry remain in `use algebra`.

Operator dispatch is still receiver-directed. Write `x*2`, not `2*x`, until
the language has a general reverse-operator protocol.
