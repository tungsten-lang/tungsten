# No explicit use. Both compiler-recognized constructor syntax and a native
# return boundary must load/register StringBuffer before public size dispatch.

-> check(name, got, expected)
  if got != expected
    << "FAIL [name]: got=[got] expected=[expected]"
    exit(1)

buffer = StringBuffer(1)
check("constructor fresh", buffer.size, 0)
ccall("w_strbuf_append", buffer, "abc\u03bb")
check("constructor live bytes", buffer.size, 5)
check("constructor stable", buffer.to_s, "abc\u03bb")

native = ccall("w_strbuf_new", 0)
ccall("w_strbuf_append", native, "hello")
check("ccall live bytes", native.size, 5)
check("ccall type", type(native), "StringBuffer")
<< "PASS StringBuffer#size constructor/ccall autoload"
