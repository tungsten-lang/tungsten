# Strict `+`: mixing a String with a non-text value raises TypeError
# instead of coercing through to_s ("5" + 3 used to yield "53").
# Text-with-text concatenation (String/Char) and interpolation keep working.
#
# Naming TypeError below is load-bearing: the reference autoloads the core
# class into this binary, so the runtime raises a real TypeError instance.
# A program that never names it gets the same error as a catchable
# "TypeError: ..." string (the bare `raise "msg"` shape).

# --- "5" + 3 raises TypeError ---
hit = false
begin
  x = "5" + 3
  << x
rescue e
  hit = true
  if e.class != TypeError
    << "FAIL: string + int expected TypeError, got [e.class]"
    exit 1
  if e.message != "no implicit conversion of Integer into String"
    << "FAIL: string + int wrong message: [e.message]"
    exit 1
if hit == false
  << "FAIL: string + int did not raise"
  exit 1

# --- 5 + "3" raises TypeError ---
hit = false
begin
  x = 5 + "3"
  << x
rescue e
  hit = true
  if e.class != TypeError
    << "FAIL: int + string expected TypeError, got [e.class]"
    exit 1
  if e.message != "String can't be coerced into Integer"
    << "FAIL: int + string wrong message: [e.message]"
    exit 1
if hit == false
  << "FAIL: int + string did not raise"
  exit 1

# --- "5" + nil raises TypeError ---
hit = false
begin
  x = "5" + nil
  << x
rescue e
  hit = true
  if e.message != "no implicit conversion of Nil into String"
    << "FAIL: string + nil wrong message: [e.message]"
    exit 1
if hit == false
  << "FAIL: string + nil did not raise"
  exit 1

# --- compound assignment takes the same path ---
hit = false
s = "count: "
begin
  s += 3
rescue e
  hit = true
if hit == false
  << "FAIL: string += int did not raise"
  exit 1

# --- text-with-text concatenation still works ---
if "a" + "b" != "ab"
  << "FAIL: string + string broke"
  exit 1
if "ab" + 'c' != "abc"
  << "FAIL: string + char broke"
  exit 1
if 'c' + "ab" != "cab"
  << "FAIL: char + string broke"
  exit 1

# --- interpolation is untouched (it lowers to to_s + concat, not +) ---
n = 42
if "n is [n]!" != "n is 42!"
  << "FAIL: interpolation broke"
  exit 1

<< "plus_type_error: all checks passed"
