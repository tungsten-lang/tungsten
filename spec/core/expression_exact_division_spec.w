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

power = (x ** -2).evaluate({x: 3})
raise "FAIL exact negative integer power" if power != Rational.new(1, 9)
raise "FAIL exact negative odd power" if (x ** -3).evaluate({x: -2}) != Rational.new(-1, 8)
raise "FAIL exact rational power" if (x ** -2).evaluate({x: Rational.new(2, 3)}) != Rational.new(9, 4)
raise "FAIL float power preserved" if (x ** -2).evaluate({x: ~3.0}).class_name != "Float"
<< "PASS exact power evaluation"
