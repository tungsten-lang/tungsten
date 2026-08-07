# Scientific-computing surface regressions: unit conversion-pipe targets
# (bare compound/mixed-case spellings), scientific-notation literals with
# units, π/τ superscript powers, %i symbol arrays, String/Number#to_d,
# Date/DateTime/UUID literals with strftime formatting, and implicit-each
# binding over a Range.
#
# Run: `bin/tungsten -o /tmp/scisurf spec/core/scientific_surface_spec.w && /tmp/scisurf`
# Also engine-parity relevant: run interpreted via `bin/tungsten run` too.

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

# -- Conversion-pipe targets: bare simple, compound, mixed-case, digits --
check("pipe.simple", (2000 m | km).to_s(), "2 km")
check("pipe.compound.slash", (5 m/s | km/h).to_s(), "18 km/h")
check("pipe.compound.digits", (5 m/s | km/h(2)).to_s(), "18 km/h")
check("pipe.compound.super", (3.5 W/m² | W/m²).to_s(), "3.5 W/m²")
check("pipe.mixedcase", (1 J | eV).to_s(), "6.242×10¹⁸ eV")
check("pipe.mixedcase.digits", (1 J | eV(3)).to_s(), "6.242×10¹⁸ eV")
check("pipe.juxta.nested", (1 atm | mmHg).to_s(), "760.0021001785 mmHg")
check("pipe.dotproduct", (1 kg·m/s | kg·m/s).to_s(), "1 kg·m/s")
check("pipe.nested.compound", (1 Jy | W/m²/Hz).to_s(), "0.00000000000000000000000001 W/m²/Hz")
check("pipe.quoted", (1 J | "eV").to_s(), "6.242×10¹⁸ eV")
check("pipe.digits.simple", (6 ft + 2 in | cm(2)).to_s(), "187.96 cm")

# Conversion pipes inside string interpolation (formatting position)
check("pipe.interp", "[340.25 W/m² | W/m²]", "340.25 W/m²")
check("pipe.interp.digits", "[5 m/s | km/h(1)]", "18 km/h")
check("pipe.interp.simple", "[0.000123 m | nm(4)]", "123000 nm")

# A local that shadows a unit-name component must keep pipe semantics for
# unrelated targets, and plain integer `|` stays bitwise-or.
h = 42
check("pipe.shadow.unrelated", (5 m/s | mph).to_s(), "11.184681460272 mph")
bx = 7
by = 3
check("pipe.int.bitor", bx | by, 7)

# -- Scientific notation with underscore grouping and unit suffixes --
check("scinot.unit", (6.626_070_15e-34 J·s).to_s(), "0.000000000000000000000000000000000662607015 J·s")
check("scinot.plain", (1.5e3 m).to_s(), "1500 m")

# -- π/τ constants and superscript powers --
check("pi.super4", π⁴ > 97.409 && π⁴ < 97.41, true)
check("pi.super5", π⁵ > 306.019 && π⁵ < 306.02, true)
check("tau", τ > 6.283 && τ < 6.284, true)

# -- Math kernels attested for scientific code --
check("math.expm1.small", Math.expm1(1e-9) > 0.0 && Math.expm1(1e-9) < 2e-9, true)
check("math.log1p.small", Math.log1p(1e-9) > 0.0 && Math.log1p(1e-9) < 1e-8, true)

# -- %i symbol arrays --
syms = %i[read write execute]
check("symarr.size", syms.size(), 3)
check("symarr.first", syms[0] == :read, true)
check("symarr.last", syms[2] == :execute, true)

# -- to_d: String parse, Decimal identity, Integer conversion --
check("to_d.string", "42.50".to_d == 42.5, true)
check("to_d.arith", ("42.50".to_d + 0.25).to_s(), "42.75")
check("to_d.bogus", "bogus".to_d.to_s(), "0")
check("to_d.decimal.identity", 42.5.to_d == 42.5, true)
check("to_d.integer", 42.to_d == 42.0, true)

# -- Date / DateTime / UUID literals and strftime formatting --
d = 2026-07-04
check("date.to_s", d.to_s(), "2026-07-04T00:00:00Z")
check("date.strftime", d.strftime("%Y/%m/%d"), "2026/07/04")
check("date.to_s.alias", d.to_s("%Y/%m/%d"), "2026/07/04")
check("date.strftime.yday", d.strftime("%j"), "185")
check("datetime.to_s", (2026-07-04T12:30:00Z).to_s(), "2026-07-04T12:30:00Z")
check("uuid.to_s", (550e8400-e29b-41d4-a716-446655440000).to_s(), "550e8400-e29b-41d4-a716-446655440000")

# -- Numeric identity predicates --
check("pred.zero", 0.zero?, true)
check("pred.one", 1.one?, true)
check("pred.one.false", 2.one?, false)

# -- Implicit each over a Range with implicit block binding --
total = 0.0
(1..5) ->
  total += 1.0 / (k * k)
check("range.implicit.binding", total.to_s(), "1.463611111111")

<< "ALL PASS scientific_surface_spec"
