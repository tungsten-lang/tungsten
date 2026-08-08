# Bare Complex — the wvalue scalar (Complex.new) coexisting with the
# generic array-backed tower (Complex<T>.new). Exact values printed so the
# interpreter and compiled outputs diff byte-identically.

z = Complex.new(3.0, 4.0)
<< "new " + z.to_s
<< "abs " + z.abs.to_s
<< "abs2 " + z.abs2.to_s
<< "real " + z.real.to_s
<< "imag " + z.imag.to_s
<< "conj " + z.conjugate.to_s
<< "neg " + z.negate.to_s

# (1+i)(2+3i) = -1+5i ; i*i = -1
<< "mul " + (Complex.new(1.0, 1.0) * Complex.new(2.0, 3.0)).to_s
<< "ii " + (Complex.i * Complex.i).to_s
<< "sq " + Complex.new(2.0, 3.0).sq.to_s

# division: (-1+5i)/(2+3i) = 1+i
<< "div " + (Complex.new(-1.0, 5.0) / Complex.new(2.0, 3.0)).to_s

# scalar mixed arithmetic
<< "adds " + (Complex.new(1.0, 2.0) + 2).to_s
<< "muls " + (Complex.new(1.0, 2.0) * 1.5).to_s

# predicates and comparison
<< "zero " + Complex.zero.zero?.to_s
<< "one " + Complex.one.one?.to_s
<< "isreal " + Complex.new(5.0, 0.0).is_real?.to_s
<< "eq " + (Complex.new(1.0, 2.0) == Complex.new(1.0, 2.0)).to_s
<< "neq " + (Complex.new(1.0, 2.0) == Complex.new(1.0, 3.0)).to_s
<< "approx " + Complex.new(1.0, 2.0).approx?(Complex.new(1.0000001, 2.0)).to_s

# power
<< "pow2 " + (Complex.new(2.0, 3.0) ** 2).to_s
<< "pow0 " + (Complex.new(2.0, 3.0) ** 0).to_s

# elementary functions (integer-rounded to stay exact across engines)
<< "expre " + (Complex.new(0.0, 0.0).exp.real.to_i).to_s
<< "sqrtn " + ((Complex.new(0.0, 2.0).sq.sqrt.imag * 1000.0).to_i).to_s
<< "argq " + ((Complex.new(3.0, 4.0).arg * 10000.0).to_i).to_s

# polar factory roundtrip: |z|=5, arg preserved through .polar
p = Complex.polar(5.0, 0.9272952180016122)
<< "polar " + p.real.round.to_s + " " + p.imag.round.to_s
