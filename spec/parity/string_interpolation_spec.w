# Strings: `[expr]` interpolation of strings, ints, expressions, nested
# brackets, symbols, booleans, arrays and hashes; escapes.
#
# Cross-engine parity spec (scripts/parity.sh).

name = "Tungsten"
n = 42
<< "interp.str hi [name]"
<< "interp.int n is [n]!"
<< "interp.expr [n * 2 + 1]"
<< "interp.nested [[1, 2, 3].size]"
<< "interp.call [name.upcase]"
<< "interp.two [n] and [name]"
<< "quote say \"hi\""
<< "backslash a\\b"
<< "newline.size [("a\nb").size]"
<< "tab.size [("a\tb").size]"
<< "bool.interp [true] [false]"
<< "arr.interp [[1, 2, true]]"
<< "hash.interp [{a: 1, b: 2}]"
<< "sym [:hello]"
<< "sym.tos [(:hello).to_s]"
<< "char.lit ['a']"
<< "int.tos [(42).to_s]"
<< "concat " + name + "!"
<< "times.zero [("x" * 0)]|"
