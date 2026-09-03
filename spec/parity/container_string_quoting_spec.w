## parity xfail to_s of an array/hash quotes string elements interpreted (["a", "b"], {name: "Alice"}) but not compiled ([a, b], {name: Alice})
# Printing: string elements inside arrays and hashes.
#
# Cross-engine parity spec (scripts/parity.sh).

<< "arr [["a", "b"]]"
<< "arr.mixed [[1, "two", :sym]]"
<< "hash [{name: "Alice", age: 30}]"
<< "hash.strkey [{"b" => 2}]"
<< "split [("a,b").split(",")]"
<< "chars [("ab").chars]"
<< "values [{k: "v"}.values]"
<< "nested [[["x"]]]"
<< ["a", "b"]
