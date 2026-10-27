# Balanced ternary

-> to_bt(n)
  if n == 0
    return "0"
  out = ""
  while n != 0
    rem = ((n % 3) + 3) % 3
    if rem == 0
      out = "0" + out
      n = n / 3
    elsif rem == 1
      out = "+" + out
      n = (n - 1) / 3
    else
      out = "-" + out
      n = (n + 1) / 3
  out

-> from_bt(s)
  chars = s.chars
  val = 0
  i = 0
  while i < chars.size
    val *= 3
    if chars[i] == "+"
      val += 1
    elsif chars[i] == "-"
      val -= 1
    i += 1
  val

a = from_bt("+-0++0+")
b = -436
c = from_bt("+-++-")
r = a * (b - c)

<< "a: [a] = [to_bt(a)]"
<< "b: [b] = [to_bt(b)]"
<< "c: [c] = [to_bt(c)]"
<< "a * (b - c): [r] = [to_bt(r)]"

## expect stdout
## a: 523 = +-0++0+
## b: -436 = -++-0--
## c: 65 = +-++-
## a * (b - c): -262023 = ----0+--0++0
