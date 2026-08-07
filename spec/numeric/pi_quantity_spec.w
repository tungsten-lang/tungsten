# π-quantities: `2π` lexes through the unit machinery (custom-unit
# fall-through, unit name "π") as an EXACT decimal multiple of π, and stays
# exact through multiplicative scaling — `2π * 50 * t` reaches Math.sin as
# an exact multiple. Evaluation boundaries collapse it to coeff·π as an
# imprecise Float: Math.*, mixed +/- with plain numerics, order
# comparisons, and to_f.
#
# The load-bearing invariant is in Math.sin/cos/tan: the exact decimal
# coefficient reduces mod 2 BEFORE any double rounding (sinpi/cospi
# semantics), so sin(1000000π) is exactly 0 — not the ~1e-10 residual that
# sin(1000000 * 3.14159…) produces — and the quarter points hit 0/±1
# exactly.
#
# Run both engines: `bin/tungsten spec/numeric/pi_quantity_spec.w`
#            and: `bin/tungsten -o /tmp/piq spec/numeric/pi_quantity_spec.w && /tmp/piq`

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()

# -- Lexing: number+π is a Quantity carrying the exact coefficient --
# NOTE: .value returns a Decimal, and `2.0 == 2` is currently false
# (type-strict ==), so the comparands below are decimal literals.
q = 2π
check("lex.type", type(q), "Quantity")
check("lex.value", q.value, 2.0)
check("lex.unit", q.unit_name, "π")

# -- Exact multiplicative algebra: scaling keeps the unit and exactness --
check("mul.int", (2π * 50).value, 100.0)
check("mul.decimal", (2π * 0.5).value, 1.0)
check("mul.float_snaps", (2π * ~0.5).value, 1.0)
check("mul.commuted", (50 * 2π).value, 100.0)
check("div.int", (2π / 2).value, 1.0)
check("mul.unit_kept", (2π * 50).unit_name, "π")

# -- Trig does the right thing: exact mod-2 reduction on the coefficient --
check("sin.whole_turn", Math.sin(2π), ~0.0)
check("sin.huge_multiple", Math.sin(1000000π), ~0.0)
check("sin.half", Math.sin(1π), ~0.0)
check("sin.quarter", Math.sin(0.5π), ~1.0)
check("sin.three_quarter", Math.sin(1.5π), ~-1.0)
check("cos.whole_turn", Math.cos(2π), ~1.0)
check("cos.half", Math.cos(1π), ~-1.0)
check("cos.quarter", Math.cos(0.5π), ~0.0)
check("tan.half", Math.tan(1π), ~0.0)
# sin(π/4) = cos(π/4) exactly after reflection into [0, ½].
check("sin.eighth_symmetry", Math.sin(0.25π) == Math.cos(0.25π), true)
check("sin.eighth_range", Math.sin(0.25π) > ~0.707 && Math.sin(0.25π) < ~0.7072, true)
# Exactness survives a chain: 2π * 50 * t with t an exact dyadic decimal.
k = 512
t = k.to_f / 1024
check("sin.chained_exact", Math.sin(2π * 50 * t), ~0.0)

# -- Evaluation boundaries: mixing with plain numerics goes imprecise --
check("add.collapses", 2π + 1 > ~7.28 && 2π + 1 < ~7.29, true)
check("sub.collapses", 1 - 2π < ~-5.28 && 1 - 2π > ~-5.29, true)
check("to_f.collapses", (2π).to_f > ~6.283 && (2π).to_f < ~6.284, true)
check("cmp.gt", 2π > 6, true)
check("cmp.lt", 2π < 6.3, true)
check("cmp.gte_float", 2π >= ~6.2, true)
# Generic Math.* evaluates the π-quantity too (no exact arm needed).
check("sqrt.collapses", Math.sqrt(2π) > ~2.5066 && Math.sqrt(2π) < ~2.5067, true)

# -- π + π stays in the exact domain (same unit, quantity addition) --
check("pi_plus_pi", (2π + 1π).value, 3.0)
check("pi_plus_pi_unit", (2π + 1π).unit_name, "π")

# -- τ-quantities: 1τ = 2π, same exactness and boundaries --
check("tau.whole_turn", Math.sin(1τ), ~0.0)
check("tau.huge_multiple", Math.sin(1000000τ), ~0.0)
check("tau.quarter_turn", Math.sin(0.25τ), ~1.0)
check("tau.cos_half", Math.cos(0.5τ), ~-1.0)
check("tau.add_collapses", 1τ + 1 > ~7.28 && 1τ + 1 < ~7.29, true)
check("tau.to_f", (1τ).to_f > ~6.283 && (1τ).to_f < ~6.284, true)
