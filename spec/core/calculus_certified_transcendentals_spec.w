# Exact rational enclosures for elementary transcendental values.

use calculus

-> enclosure_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

tolerance = Rational.new(1, 10**22)

pi_value = Calculus.certified_pi(tolerance)
enclosure_check(
  "pi.decimal_bracket",
  pi_value.lower_bound >
    Rational.new(314159265358979323846, 10**20) &&
  pi_value.upper_bound <
    Rational.new(314159265358979323847, 10**20))
enclosure_check("pi.width", pi_value.width <= tolerance)
enclosure_check("pi.certificate", pi_value.certified?)

e_value = Calculus.certified_e(tolerance)
enclosure_check(
  "e.decimal_bracket",
  e_value.lower_bound >
    Rational.new(271828182845904523536, 10**20) &&
  e_value.upper_bound <
    Rational.new(271828182845904523537, 10**20))
enclosure_check("e.certificate", e_value.certified?)

log_two = Calculus.certified_log(2, tolerance)
enclosure_check(
  "log2.decimal_bracket",
  log_two.lower_bound >
    Rational.new(69314718055994530941, 10**20) &&
  log_two.upper_bound <
    Rational.new(69314718055994530942, 10**20))
enclosure_check("log1.exact",
                Calculus.certified_log(1).interval ==
                CertifiedRealInterval.new(0, 0))

sin_one = Calculus.certified_sin(1, tolerance)
cos_one = Calculus.certified_cos(1, tolerance)
enclosure_check(
  "sin1.decimal_bracket",
  sin_one.lower_bound >
    Rational.new(84147098480789650665, 10**20) &&
  sin_one.upper_bound <
    Rational.new(84147098480789650666, 10**20))
enclosure_check(
  "cos1.decimal_bracket",
  cos_one.lower_bound >
    Rational.new(54030230586813971740, 10**20) &&
  cos_one.upper_bound <
    Rational.new(54030230586813971741, 10**20))
enclosure_check(
  "sin.odd",
  Calculus.certified_sin(-1, tolerance).interval ==
  sin_one.interval.negate)
enclosure_check(
  "cos.even",
  Calculus.certified_cos(-1, tolerance).interval ==
  cos_one.interval)

atan_one = Calculus.certified_atan(1, tolerance)
enclosure_check(
  "atan1.decimal_bracket",
  atan_one.lower_bound >
    Rational.new(78539816339744830961, 10**20) &&
  atan_one.upper_bound <
    Rational.new(78539816339744830962, 10**20))

positive = Calculus.certified_exp(2, tolerance)
negative = Calculus.certified_exp(-2, tolerance)
enclosure_check(
  "exp.reciprocal_identity",
  (positive.interval*negative.interval).contains?(1))

bad_domain = false
begin
  Calculus.certified_log(0)
rescue error
  bad_domain = true
enclosure_check("log.domain_rejected", bad_domain)

bounded_failure = false
begin
  Calculus.certified_exp(
    100, Rational.new(1, 10**100), 2)
rescue error
  bounded_failure = true
enclosure_check("exp.resource_bound", bounded_failure)

bad_certificate = CertifiedTranscendentalCertificate.new(
  "not a transcendental value")
enclosure_check("certificate.tamper_rejected",
                !bad_certificate.verified?)
