# Expression-local `## type` ascriptions must work inside parentheses and
# call arguments, not only as the trailing hint on an assignment.

-> identity(value)
  value

-> nested(value)
  ((value ## i64) + (identity(2 ## i64) ## i64)) ## i64

if nested(40) != 42
  << "FAIL nested type ascription"
  exit(1)
<< "PASS nested type ascription"
