# A source override must disable cancellation, including the equal-bound fold.
$factorial_calls = 0
+ Int
  -> factorial
    $factorial_calls += 1
    self + 7

-> check(name, got, want)
  if got != want
    << "FAIL [name]: got=[got] want=[want]"
    exit(1)

check("override suffix", 10!, 17)
check("override quotient", 10! / 5!, 1)
check("override method quotient", 10.factorial / 5.factorial, 1)
check("override equal quotient", 10! / 10!, 1)
check("override side effects", $factorial_calls, 7)
<< "PASS factorial quotient override"
