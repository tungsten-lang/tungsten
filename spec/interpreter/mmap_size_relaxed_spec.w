# Tree-walker parity for Mmap construction, type discovery, source size field,
# and retained native methods after core/file becomes autoloadable.

-> check(name, got, expected)
  if got != expected
    << "FAIL [name]: got=[got] expected=[expected]"
    exit(1)

# Exercise the direct constructor first: referencing File earlier would load
# core/mmap and mask a broken runtime-type-driven lazy autoload path.
native = ccall("__w_file_mmap", "VERSION")
native_size = native.size
check("direct ccall index parity", native.byte_at(0), native[0])
native.close

mapping = File.mmap("VERSION")
expected = mapping.size
check("direct ccall size", native_size, expected)
check("index parity", mapping.byte_at(0), mapping[0])
mapping.close
check("size survives close", mapping.size, expected)
<< "PASS interpreted Mmap#size autoload/view/retained-native parity"
