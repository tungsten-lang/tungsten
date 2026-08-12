# Every public StringBuffer operation must survive receiver type erasure at a
# function boundary. These calls use the native IC table in compiled code and
# the same runtime surface in the self-hosted interpreter.

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

-> exercise(buffer)
  buffer.append("h\0\u00e9")
  buffer << 42
  check("strbuf.dynamic.text", buffer.to_s(), "h\0\u00e942")
  check("strbuf.dynamic.size", buffer.size(), 6)
  check("strbuf.dynamic.byte_size", buffer.byte_size(), 6)
  check("strbuf.dynamic.index", buffer[0], "h")
  check("strbuf.dynamic.negative_index", buffer[-1], "2")
  check("strbuf.dynamic.empty.false", buffer.empty?(), false)
  check("strbuf.dynamic.include", buffer.include?("\0\u00e9"), true)
  check("strbuf.dynamic.starts_with", buffer.starts_with?("h\0\u00e9"), true)
  returned = buffer.clear()
  check("strbuf.dynamic.clear.return", returned == buffer, true)
  check("strbuf.dynamic.empty.true", buffer.empty?(), true)

exercise(StringBuffer(4))
<< "string_buffer_dynamic_receiver_spec: all checks passed"
