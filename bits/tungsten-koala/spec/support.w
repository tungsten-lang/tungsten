# Numeric-tolerance matchers for the koala specs.
#
# Float#to_s now prints an f64 at FULL precision (`%.17g`, which round-trips)
# rather than the old six-significant-digit `%g`. The readable expected
# values in these specs (e.g. "0.666667") therefore no longer match a raw
# `.to_s` by string equality even though the VALUE is correct. These
# matchers compare by NUMERIC TOLERANCE instead: the expected literal stays
# readable and platform-stable, and a relative tolerance of 1e-5 absorbs the
# sixth-significant-digit rounding of the expected while still rejecting any
# genuinely wrong result (a real error differs by far more than 1e-5).
#
#   expect(Metrics.accuracy(a, b)).to be_num("0.666667")
#   expect(row.join(",")).to be_nums("4,2.5,1.29099,1,1.75,2.5,3.25,4")
#   expect(qr[0].to_a.to_s).to be_nums("\[\[-0.6, 0.8\], \[-0.8, -0.6\]\]")
#
# be_num takes a scalar (a number or its string). be_nums takes a joined row
# or a nested-array `.to_s`; it pulls out every numeric token (ignoring commas,
# brackets and spaces) and compares element for element.

use spec

# Pull the numeric tokens out of a rendered value. Brackets and spaces are
# separators just like commas, so this handles a flat "a,b,c" join and a
# nested "[[a, b], [c, d]]" to_s alike. Bracket characters are built from
# codepoints because a literal `[` interpolates inside a string.
-> koala_num_tokens(s)
  lb = 91.chr
  rb = 93.chr
  sp = 32.chr
  toks = []
  cur = ""
  i = 0
  n = s.size
  while i < n
    c = s[i]
    if c == "," || c == lb || c == rb || c == sp
      if cur != ""
        toks.push(cur)
        cur = ""
    else
      cur = cur + c
    i += 1
  if cur != ""
    toks.push(cur)
  toks

# Two f64s agree if they are within a relative 1e-5 (with a tiny absolute
# floor for values at or near zero). Both arguments are converted to f64 by
# the callers; the arithmetic here is f64 throughout.
-> koala_num_close(a, b)
  d = a - b
  if d < 0.to_f
    d = 0.to_f - d
  m = b
  if m < 0.to_f
    m = 0.to_f - m
  tol = m * 0.00001.to_f
  floor = 0.000000000001.to_f
  if tol < floor
    tol = floor
  d <= tol

-> be_num(expected)
  NumMatcher.new(expected)

+ NumMatcher
  ro :expected

  -> new(@expected)

  -> matches?(actual)
    koala_num_close(actual.to_f, @expected.to_f)

  -> failure_message(actual)
    "expected ~[@expected] but got [actual]"

  -> negated_failure_message(actual)
    "expected anything but ~[@expected]"

-> be_nums(expected)
  NumsMatcher.new(expected)

+ NumsMatcher
  ro :expected

  -> new(@expected)

  -> matches?(actual)
    ap = koala_num_tokens(actual.to_s)
    ep = koala_num_tokens(@expected)
    if ap.size != ep.size
      return false
    ok = true
    i = 0
    while i < ep.size
      if !koala_num_close(ap[i].to_f, ep[i].to_f)
        ok = false
      i += 1
    ok

  -> failure_message(actual)
    "expected ~[@expected] but got [actual]"

  -> negated_failure_message(actual)
    "expected anything but ~[@expected]"
