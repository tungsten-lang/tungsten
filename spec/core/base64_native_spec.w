# RFC 4648 parity for the source-defined Base64/Base64URL codecs. This file is
# run both compiled and through `tungsten run` by scripts/test-specs.sh.

-> fail_check(name, detail = "")
  << "FAIL: [name] [detail]"
  exit(1)

-> check(name, got, expected)
  if got != expected
    fail_check(name, "got=[got] expected=[expected]")

-> check_bytes(name, got, expected)
  if got.size != expected.size
    fail_check(name, "size got=[got.size] expected=[expected.size]")
  i = 0
  while i < got.size
    if got[i] != expected[i]
      fail_check(name, "byte [i] got=[got[i]] expected=[expected[i]]")
    i += 1

-> bytes_for(text)
  Base64.decode(Base64.encode(text))

# RFC 4648 section 10 vectors, including every 1/2/3-byte tail shape.
inputs = ["", "f", "fo", "foo", "foob", "fooba", "foobar"]
standard = ["", "Zg==", "Zm8=", "Zm9v", "Zm9vYg==", "Zm9vYmE=", "Zm9vYmFy"]
urlsafe = ["", "Zg", "Zm8", "Zm9v", "Zm9vYg", "Zm9vYmE", "Zm9vYmFy"]
i = 0
while i < inputs.size
  check("standard encode [i]", Base64.encode(inputs[i]), standard[i])
  check("global encode [i]", base64_encode(inputs[i]), standard[i])
  check("url encode [i]", Base64.url_encode(inputs[i]), urlsafe[i])
  check("global url encode [i]", base64url_encode(inputs[i]), urlsafe[i])
  check_bytes("standard decode [i]", Base64.decode(standard[i]), bytes_for(inputs[i]))
  check_bytes("global decode [i]", base64_decode(standard[i]), bytes_for(inputs[i]))
  check_bytes("url decode [i]", Base64.url_decode(urlsafe[i]), bytes_for(inputs[i]))
  check_bytes("global url decode [i]", base64url_decode(urlsafe[i]), bytes_for(inputs[i]))
  i += 1

# Alphabet split and URL-safe no-padding behavior.
alphabet_bytes = u8[3]
alphabet_bytes[0] = 0xFB
alphabet_bytes[1] = 0xFF
alphabet_bytes[2] = 0xFF
check("standard alphabet", Base64.encode(alphabet_bytes), "+///")
check("url alphabet", Base64.url_encode(alphabet_bytes), "-___")
check_bytes("standard alphabet decode", Base64.decode("+///"), alphabet_bytes)
check_bytes("url alphabet decode", Base64.url_decode("-___"), alphabet_bytes)

# Optional trailing '=' is accepted by both decoders; '=' in the body is not.
check_bytes("standard trailing padding", Base64.decode("Zm9v===="), bytes_for("foo"))
check_bytes("url trailing padding", Base64.url_decode("Zm9v===="), bytes_for("foo"))
empty_bytes = u8[0]
one_zero = u8[1]
two_zero = u8[2]
three_zero = u8[3]
check_bytes("short group 1", Base64.decode("A"), empty_bytes)
check_bytes("short group 2", Base64.decode("AA"), one_zero)
check_bytes("short group 3", Base64.decode("AAA"), two_zero)
check_bytes("short group 5", Base64.decode("AAAAA"), three_zero)
check_bytes("all padding", Base64.decode("===="), empty_bytes)
check_bytes("one char plus padding", Base64.decode("A==="), empty_bytes)
check_bytes("url short group 2", Base64.url_decode("AA"), one_zero)
check_bytes("url excessive padding", Base64.url_decode("Zg====="), bytes_for("f"))

# String and ByteArray encoders share byte semantics, including embedded NUL.
nul_bytes = u8[3]
nul_bytes[0] = 65
nul_bytes[1] = 0
nul_bytes[2] = 66
nul_string = ccall("w_string_from_byte_array", nul_bytes)
check("ByteArray embedded NUL", Base64.encode(nul_bytes), "QQBC")
check("String embedded NUL", Base64.encode(nul_string), "QQBC")
check_bytes("embedded NUL decode", Base64.decode("QQBC"), nul_bytes)

# NUL inside encoded text is data too: it is not an alphabet member and must
# raise instead of silently truncating at the NUL as the former strlen path did.
nul_encoded_bytes = u8[5]
nul_encoded_bytes[0] = 90
nul_encoded_bytes[1] = 103
nul_encoded_bytes[2] = 0
nul_encoded_bytes[3] = 61
nul_encoded_bytes[4] = 61
nul_encoded = ccall("w_string_from_byte_array", nul_encoded_bytes)
nul_encoded_hit = false
begin
  Base64.decode(nul_encoded)
rescue e
  nul_encoded_hit = true
if !nul_encoded_hit
  fail_check("embedded NUL encoded text did not raise")

# Deterministic size scaling catches allocation/count and tail regressions.
size = 0
while size <= 257
  raw = u8[size]
  i = 0
  while i < size
    raw[i] = (i * 73 + size * 19 + 11) & 0xFF
    i += 1
  check_bytes("scaled standard [size]", Base64.decode(Base64.encode(raw)), raw)
  check_bytes("scaled url [size]", Base64.url_decode(Base64.url_encode(raw)), raw)
  size += 1

# Invalid characters and non-trailing padding raise on the source path.
bad_standard = false
begin
  Base64.decode("Zm-9")
rescue e
  bad_standard = true
if !bad_standard
  fail_check("standard invalid character did not raise")

bad_url = false
begin
  Base64.url_decode("Zm+9")
rescue e
  bad_url = true
if !bad_url
  fail_check("url invalid character did not raise")

bad_padding = false
begin
  Base64.decode("Z=m9")
rescue e
  bad_padding = true
if !bad_padding
  fail_check("embedded padding did not raise")

<< "base64_native: all checks passed"
