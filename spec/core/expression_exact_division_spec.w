# Integer bindings in exact symbolic quotients retain the fraction.
# Run interpreted and native.

use expression

x = Expression.variable(:x)
value = (Expression.constant(2) / x).evaluate({x: 5})
raise "FAIL expression exact integer division" if value != Rational.new(2, 5)
<< "PASS expression exact integer division"

machine_five = 5 ## i64
machine_value = (Expression.constant(2) / x).evaluate({x: machine_five})
if machine_value != Rational.new(2, 5)
  raise "FAIL expression exact machine-int division"
<< "PASS expression exact machine-int division"

wide = "1208925819614629174706177".to_i
wide_value = (Expression.constant(2) / x).evaluate({x: wide})
if wide_value != Rational.new(2, wide)
  raise "FAIL expression exact bignum division"
<< "PASS expression exact bignum division"
