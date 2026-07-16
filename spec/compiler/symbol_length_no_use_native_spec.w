# Independent length-name gate for an unknown heap Symbol with embedded NUL.
-> probe(value)
  value.length

value = ccall("w_strlen_fixture", 15)
got = probe(value)
if got != 80
  << "FAIL no-use native Symbol#length got=[got]"
  exit(1)
<< "PASS no-use native Symbol#length"
