# No explicit use. This digit-first UUID literal names no class, so loader
# literal autoload is solely responsible for registering UUID#byte.

-> check(name, got, expected)
  if got != expected
    << "FAIL [name]: got=[got] expected=[expected]"
    exit(1)

uuid = 00112233-4455-6677-8899-aabbccddeeff
check("literal byte 0", uuid.byte(0), 0x00)
check("literal byte 15", uuid.byte(15), 0xff)
check("literal lower bound", uuid.byte(-1), nil)
check("literal upper bound", uuid.byte(16), nil)
check("literal type", type(uuid), "UUID")
check("literal stable", uuid.to_s, "00112233-4455-6677-8899-aabbccddeeff")

# A native-return boundary is a second class-less source shape.
parsed = ccall("w_uuid_parse", "ffeeddcc-bbaa-6988-8766-554433221100")
check("ccall byte", parsed.byte(0), 0xff)
check("ccall stable", parsed.to_s, "ffeeddcc-bbaa-6988-8766-554433221100")
<< "PASS UUID#byte literal/ccall autoload"
