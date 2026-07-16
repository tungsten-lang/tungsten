# No explicit use: File.mmap must register Mmap's source-backed size method
# after the native IC is removed. The direct native-return form has a separate
# spec so neither whole-AST trigger can mask the other.

-> check(name, got, expected)
  if got != expected
    << "FAIL [name]: got=[got] expected=[expected]"
    exit(1)

mapping = File.mmap("VERSION")
expected = mapping.size
check("File.mmap type", type(mapping), "Mmap")
check("index parity", mapping.byte_at(0), mapping[0])
mapping.close
check("size survives close", mapping.size, expected)
<< "PASS Mmap#size File.mmap autoload"
