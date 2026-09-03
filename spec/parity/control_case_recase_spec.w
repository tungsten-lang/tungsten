# Control flow: case/when with values, lists, ranges and strings;
# condition-only case; recase; unless; ternary; if as a value; and/or.
#
# Cross-engine parity spec (scripts/parity.sh).

-> classify(n)
  case n
  when 0
    "zero"
  when 1, 2
    "small"
  else
    "big"
<< "case [classify(0)] [classify(2)] [classify(50)]"
-> kind(s)
  case s
  when "a"
    1
  when "b"
    2
  else
    0
<< "case.str [kind("a")] [kind("b")] [kind("z")]"
-> sign(n)
  case
  when n > 0
    "pos"
  when n < 0
    "neg"
  else
    "zero"
<< "case.cond [sign(3)] [sign(-3)] [sign(0)]"
-> countdown(cell)
  case cell[0]
  when 0
    "zero"
  when 1
    "one"
  when 2
    "two"
  else
    cell[0] = cell[0] - 1
    recase cell[0]
<< "recase [countdown([5])]"
-> ramp(c)
  case
  when c[0] >= 3
    c[0]
  else
    c[0] = c[0] + 1
    recase
<< "recase.bare [ramp([0])]"
-> guard(n)
  "small" unless n > 10
<< "unless [guard(1)]"
-> tern(n)
  n > 0 ? "yes" : "no"
<< "ternary [tern(1)] [tern(0)]"
-> ifv(n)
  r = if n > 0
    "p"
  else
    "n"
  r
<< "if.value [ifv(1)] [ifv(-1)]"
<< "or [nil || "dflt"] and [1 && 2]"
<< "truthy [0 ? "t" : "f"] [("" ? "t" : "f")] [([] ? "t" : "f")]"
