# Class-side overloads share a source name but must keep distinct native ABIs.

+ StaticOverloadProbe
  -> .pick(value)
    "one:" + value.to_s

  -> .pick(a, b, c)
    "three:" + (a + b + c).to_s

if StaticOverloadProbe.pick(7) != "one:7"
  << "FAIL one-argument static overload"
  exit(1)
if StaticOverloadProbe.pick(1, 2, 3) != "three:6"
  << "FAIL three-argument static overload"
  exit(1)

<< "PASS static method overloads"
