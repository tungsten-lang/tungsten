# Specialization into smaller rings, name-based re-embedding, divisibility.
# Reopens Polynomial; load after polynomial.w / polynomial_gcd.w.
#
# `substitute` keeps a polynomial in its original ring with the substituted
# variable's exponent set to zero. The univariate routines (coefficients,
# factor, xgcd, resultant) need a ring of arity one, so `specialize` removes
# the variable from the ring as well: it is the ring map F[x, z] -> F[x],
# z |-> value, with the result living in F[x].

+ Polynomial
  # self divides other (division by one polynomial has zero remainder iff
  # it divides, because {self} is a Groebner basis of the ideal it generates).
  -> divides?(other)
    other = coerce(other)
    return other.zero? if zero?
    other.rem(self).zero?

  # Re-embed by generator names into `target`. Every variable that occurs
  # with a positive exponent must exist in the target ring.
  -> in_ring(target)
    raise "in_ring needs a PolynomialRing" if target.class_name != "PolynomialRing"
    mapping = []
    i = 0
    while i < @ring.arity
      mapping.push(target.index_of(@ring.names[i]))
      i += 1
    out = []
    @terms.each -> (term)
      exponents = target.zero_exponents
      j = 0
      while j < term[1].size
        if term[1][j] > 0
          raise "in_ring: variable is not in the target ring" if mapping[j] == nil
          exponents[mapping[j]] = term[1][j]
        j += 1
      out.push([term[0], exponents])
    Polynomial.new(target, out)

  # The ring without one generator, same field and order.
  -> ring_without(variable)
    index = substitution_index(variable)
    raise "specialize: a univariate polynomial specializes to a scalar; use at" if @ring.arity == 1
    names = []
    i = 0
    while i < @ring.arity
      names.push(@ring.names[i]) if i != index
      i += 1
    PolynomialRing.new(names, @ring.field, @ring.order)

  # Specialize one variable and drop it from the ring.
  -> specialize(variable, value)
    substitute(variable, value).in_ring(ring_without(variable))
