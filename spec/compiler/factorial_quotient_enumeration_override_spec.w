# Factorial's source dependencies matter as well as factorial itself.
+ Range
  -> reduce(init, &block)
    7

if 10! / 5! != 1
  << "FAIL factorial quotient ignored Range#reduce override"
  exit(1)
<< "PASS factorial quotient enumeration override"
