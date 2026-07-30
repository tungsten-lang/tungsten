# Certified Tate local data over Q.
#
# The expected Kodaira symbols, conductor exponents, Tamagawa numbers, and
# split flags below are differential fixtures from Sage 10.9.

use algebra

-> tate_check(name, got, want)
  if got != want
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

-> check_local(name, model, prime, symbol, exponent, tamagawa, split)
  data = model.tate_local_data(prime)
  tate_check(name + ".symbol", data.kodaira_symbol, symbol)
  tate_check(name + ".exponent", data.conductor_exponent, exponent)
  tate_check(name + ".tamagawa", data.tamagawa_number, tamagawa)
  tate_check(name + ".split", data.split?, split)
  tate_check(name + ".certificate", data.certificate.verified?, true)
  data

# Wild additive reduction at 2 and 3 exercises branches that cannot be
# inferred from v(c4) and v(Delta) alone.
minus_x = IntegralWeierstrassModel.new(0, 0, 0, -1, 0)
minus_x_at_2 = check_local(
  "minus_x_at_2", minus_x, 2, "III", 5, 2, nil)
tate_check("minus_x.local_reduction_exponent",
           minus_x.local_reduction(2).conductor_exponent, 5)

unit_sextic = IntegralWeierstrassModel.new(0, 0, 0, 0, 1)
check_local("unit_sextic_at_2", unit_sextic, 2, "IV", 2, 3, nil)
check_local("unit_sextic_at_3", unit_sextic, 3, "III", 2, 2, nil)

five_sextic = IntegralWeierstrassModel.new(0, 0, 0, 0, 5)
check_local("five_sextic_at_2", five_sextic, 2, "IV", 2, 1, nil)
check_local("five_sextic_at_3", five_sextic, 3, "II", 3, 1, nil)
check_local("five_sextic_at_5", five_sextic, 5, "II", 2, 1, nil)
tate_check("five_sextic.conductor", five_sextic.conductor, 2700)
tate_check("five_sextic.conductor_certificate",
           five_sextic.conductor_computation.certificate.verified?, true)

# Together these tame fixtures cover every additive Kodaira branch.
check_local(
  "iv_at_5", IntegralWeierstrassModel.new(0, 0, 0, 0, 25),
  5, "IV", 2, 3, nil)
check_local(
  "i0_star_at_5", IntegralWeierstrassModel.new(0, 0, 0, 0, 125),
  5, "I0*", 2, 2, nil)
check_local(
  "iv_star_at_5", IntegralWeierstrassModel.new(0, 0, 0, 0, 625),
  5, "IV*", 2, 3, nil)
check_local(
  "ii_star_at_5", IntegralWeierstrassModel.new(0, 0, 0, 0, 3125),
  5, "II*", 2, 1, nil)
check_local(
  "iii_at_5", IntegralWeierstrassModel.new(0, 0, 0, 5, 0),
  5, "III", 2, 2, nil)
check_local(
  "iii_star_at_5", IntegralWeierstrassModel.new(0, 0, 0, 125, 0),
  5, "III*", 2, 2, nil)

# Representative I0*, I1*, and IV* branches at 2.
check_local(
  "i0_star_at_2",
  IntegralWeierstrassModel.new(0, -1, 0, -1, -3),
  2, "I0*", 4, 1, nil)
check_local(
  "i1_star_at_2",
  IntegralWeierstrassModel.new(0, 0, 0, 1, 2),
  2, "I1*", 3, 4, nil)
check_local(
  "iv_star_at_2",
  IntegralWeierstrassModel.new(0, 1, 0, 3, -1),
  2, "IV*", 2, 3, nil)

# Good and multiplicative reduction retain their standard local data.
check_local(
  "good_at_2",
  IntegralWeierstrassModel.new(0, 0, 1, -1, 0),
  2, "I0", 0, 1, nil)
e11 = IntegralWeierstrassModel.new(0, -1, 1, 0, 0)
check_local("split_i1_at_11", e11, 11, "I1", 1, 1, true)

# The hard Frey orientation is wild additive at 2. Full conductor assembly is
# now finite and certified rather than returning `unknown`.
frey = FreyCurve.new(2, 3, 5)
frey_at_2 = check_local(
  "frey_at_2", frey.model, 2, "I6*", 4, 4, nil)
tate_check("frey.conductor", frey.conductor, 2640)
tate_check("frey.conductor_certificate",
           frey.model.conductor_computation.certificate.verified?, true)

bad = EllipticTateLocalDataCertificate.new(
  minus_x_at_2.source, minus_x_at_2.prime,
  minus_x_at_2.minimality_certificate,
  minus_x_at_2.kind, 4, minus_x_at_2.kodaira_symbol,
  minus_x_at_2.tamagawa_number, minus_x_at_2.split?,
  minus_x_at_2.transformations, minus_x_at_2.final_model, 250_000)
tate_check("tampered_exponent_rejected", bad.verified?, false)
