# Interpreter parity for strict `+`: "5" + 3 and 5 + "3" raise a
# TypeError instead of coercing. The interpreter's raise machinery is
# string-based, so the rescued value is the "TypeError: ..." message.

hit = false
begin
  x = "5" + 3
  << x
rescue e
  hit = true
  if "[e]".include?("TypeError: no implicit conversion of Integer into String") == false
    << "FAIL: string + int wrong error: [e]"
    exit 1
if hit == false
  << "FAIL: string + int did not raise"
  exit 1

hit = false
begin
  x = 5 + "3"
  << x
rescue e
  hit = true
  if "[e]".include?("TypeError: String can't be coerced into Integer") == false
    << "FAIL: int + string wrong error: [e]"
    exit 1
if hit == false
  << "FAIL: int + string did not raise"
  exit 1

# Text-with-text still concatenates; interpolation is untouched.
if "a" + "b" != "ab"
  << "FAIL: string + string broke"
  exit 1
if "ab" + 'c' != "abc"
  << "FAIL: string + char broke"
  exit 1
n = 42
if "n is [n]!" != "n is 42!"
  << "FAIL: interpolation broke"
  exit 1

<< "plus_type_error interpreter: all checks passed"
