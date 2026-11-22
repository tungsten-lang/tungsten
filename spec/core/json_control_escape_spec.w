# JSON.encode must escape every U+0000..U+001F (RFC 8259); it used to emit
# U+000B, U+0001, ... raw. JSON.parse now decodes \b, \f and \uXXXX (with
# surrogate pairs) instead of dropping the backslash.

$failures = 0

-> check(label, got, want)
  if got != want
    << "FAIL [label]: got [got], want [want]"
    $failures = $failures + 1

-> raw_controls(s)
  bad = 0
  i = 0
  while i < s.size
    bad += 1 if s.byte_at(i) < 32
    i += 1
  bad

s = "a" + 11.chr + "b" + 1.chr + "c" + 8.chr + 12.chr + 9.chr + 31.chr
out = JSON.encode([s])
check("no raw control bytes", raw_controls(out), 0)
check("escapes", out.size, 31)
check("round trip", JSON.parse(out)[0] == s, true)
short = 1.chr + "x"
check("short string", JSON.encode(short).size, 9)
long = "0123456789" + 2.chr + "abcdefghijklmnop"
check("long string", raw_controls(JSON.encode(long)), 0)
q = 34.chr
bs = 92.chr
check("parse u escape", JSON.parse(q + bs + "u00e9" + q), "é")
check("parse surrogate pair", JSON.parse(q + bs + "ud83d" + bs + "ude00" + q).size, 4)
check("parse b f", JSON.parse(q + bs + "b" + bs + "f" + q), 8.chr + 12.chr)

if $failures > 0
  exit(1)
<< "PASS json control escape"
