# Tree-walker parity for the source-backed UUID byte load and lazy core load.

-> check(name, got, expected)
  if got != expected
    << "FAIL [name]: got=[got] expected=[expected]"
    exit(1)

uuid = UUID.parse("00112233-4455-6677-8899-aabbccddeeff")
expected = [0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77,
            0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff]
i = 0
while i < expected.size
  check("byte [i]", uuid.byte(i), expected[i])
  i += 1
check("negative", uuid.byte(-1), nil)
check("past end", uuid.byte(16), nil)
check("BigInt bound", uuid.byte(281474976710656), nil)
check("BigInt low-i64 wrap", uuid.byte(18446744073709551616), 0x00)
check("surplus argument", uuid.byte(1, "ignored"), 0x11)
check("receiver stable", uuid.to_s, "00112233-4455-6677-8899-aabbccddeeff")
<< "PASS interpreted UUID#byte source storage/autoload"
