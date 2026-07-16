# `/N` belongs to a method definition only after `-> name`. In an expression,
# an identifier immediately followed by `/integer` is ordinary division with
# the same precedence as its spaced spelling.

-> add/2
  @1 + @2

-> quotient(value)
  value/10

-> precedence(value)
  value/10**2

failures=0 ## i64
if quotient(120)!=12
  failures+=1
if precedence(1000)!=10
  failures+=1
if add(7,8)!=15
  failures+=1

if failures!=0
  << "FAIL no-space identifier division failures="+failures.to_s()
  exit(1)
<< "PASS no-space identifier division"
