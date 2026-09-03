# Strings: the ESC-bracket rule — `\e[` starts a terminal escape, not an
# interpolation, and `\[` is a literal bracket.
#
# Cross-engine parity spec (scripts/parity.sh).

esc = "\e[K"
<< "esc.size [esc.size]"
<< "esc.byte0 [esc.bytes[0]]"
n = 7
lit = "\[n]"
<< "lit.bracket [lit]"
<< "lit.size [lit.size]"
<< "mixed \[[n]]"
red = "\e[31mred\e[0m"
<< "red.size [red.size]"
