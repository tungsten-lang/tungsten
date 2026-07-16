# Symbol has no distinct compiled dispatch key; unknown native Symbols must
# reach String's shared 0xF9 source size body without loading symbol.w.
-> probe(value)
  value.size

value = ccall("w_strlen_fixture", 12)
got = probe(value)
if got != 6
  << "FAIL no-use native Symbol#size got=[got]"
  exit(1)
<< "PASS no-use native Symbol#size"
