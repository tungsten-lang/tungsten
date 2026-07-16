# Tree-walker parity for direct StringBuffer view-field size loads.

-> check(name, got, expected)
  if got != expected
    << "FAIL [name]: got=[got] expected=[expected]"
    exit(1)

buffer = StringBuffer(1)
check("fresh", buffer.size, 0)
ccall("w_strbuf_append", buffer, "abc")
check("ASCII", buffer.size, 3)
ccall("w_strbuf_append", buffer, "\u03bb")
check("UTF-8 bytes", buffer.size, 5)
check("surplus argument", buffer.size("ignored"), 5)
check("representation", buffer.class_name, "StringBuffer")
check("stable", buffer.to_s, "abc\u03bb")
<< "PASS interpreted StringBuffer#size view/autoload"
