# A direct native constructor must independently register Mmap. Keep this file
# free of File.mmap: the loader walks the whole AST, so combining both forms in
# one spec would let the File trigger mask a broken native-return trigger.

-> check(name, got, expected)
  if got != expected
    << "FAIL [name]: got=[got] expected=[expected]"
    exit(1)

mapping = ccall("__w_file_mmap", "VERSION")
expected = File.size("VERSION")
check("native-only type", type(mapping), "Mmap")
check("native-only size", mapping.size, expected)
check("native-only index parity", mapping.byte_at(0), mapping[0])
mapping.close
check("native-only size survives close", mapping.size, expected)
<< "PASS Mmap#size direct-native autoload"
