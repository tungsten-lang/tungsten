# Function-level A/B benchmark for Base64/Base64URL moved from runtime.c to
# core/base64.w. C references are linked into this executable only.

DEFAULT_ITERS = 20_000
WARMUP_ITERS = 500

+ Base64
  -> .__c_encode(data)
    ccall("w_ref_base64_encode", data)

  -> .__c_decode(text)
    ccall("w_ref_base64_decode", text)

  -> .__c_url_encode(data)
    ccall("w_ref_base64url_encode", data)

  -> .__c_url_decode(text)
    ccall("w_ref_base64url_decode", text)

-> fail_check(name, detail = "")
  << "FAIL [name] [detail]"
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
      fail_check(name, "byte=[i] got=[got[i]] expected=[expected[i]]")
    i += 1

-> deterministic_bytes(size, salt = 0)
  out = u8[size]
  i = 0
  while i < size
    out[i] = (i * 73 + size * 19 + salt * 29 + 11) & 0xFF
    i += 1
  out

-> ascii_string(size)
  bytes = u8[size]
  i = 0
  while i < size
    bytes[i] = 33 + (i * 47 + size * 13) % 94
    i += 1
  ccall("w_string_from_byte_array", bytes)

-> run_correctness
  checked = 0

  # Exact size-scaled C/W parity for ByteArray inputs and non-NUL Strings.
  size = 0
  while size <= 1024
    raw = deterministic_bytes(size, 7)
    text = ascii_string(size)
    check("encode.bytes.[size]", Base64.encode(raw), Base64.__c_encode(raw))
    check("encode.string.[size]", Base64.encode(text), Base64.__c_encode(text))
    check("url_encode.bytes.[size]", Base64.url_encode(raw), Base64.__c_url_encode(raw))
    check("url_encode.string.[size]", Base64.url_encode(text), Base64.__c_url_encode(text))
    check_bytes("decode.[size]", Base64.decode(Base64.__c_encode(raw)), raw)
    check_bytes("decode.cw.[size]", Base64.__c_decode(Base64.encode(raw)), raw)
    check_bytes("url_decode.[size]", Base64.url_decode(Base64.__c_url_encode(raw)), raw)
    check_bytes("url_decode.cw.[size]", Base64.__c_url_decode(Base64.url_encode(raw)), raw)
    checked += 8
    size += 1

  # Former decoders intentionally accepted short groups, arbitrary trailing
  # padding, and even all-padding input. Preserve those exact edge semantics.
  malformed = ["", "A", "AA", "AAA", "AAAA", "AAAAA", "A=", "A===",
               "Zg=", "Zg==", "Zg=====", "Zm8=", "Zm9v=", "===="]
  i = 0
  while i < malformed.size
    check_bytes("decode.edge.[i]", Base64.decode(malformed[i]), Base64.__c_decode(malformed[i]))
    check_bytes("url_decode.edge.[i]", Base64.url_decode(malformed[i]), Base64.__c_url_decode(malformed[i]))
    checked += 2
    i += 1

  # Invalid alphabet members/non-trailing '=' raise in both implementations.
  invalid_standard = ["Zm-9", "Zm_9", "Z=m9", "Zm9v!"]
  i = 0
  while i < invalid_standard.size
    c_hit = false
    w_hit = false
    begin
      Base64.__c_decode(invalid_standard[i])
    rescue e
      c_hit = true
    begin
      Base64.decode(invalid_standard[i])
    rescue e
      w_hit = true
    check("invalid.standard.c.[i]", c_hit, true)
    check("invalid.standard.w.[i]", w_hit, true)
    checked += 2
    i += 1

  invalid_url = ["Zm+9", "Zm/9", "Z=m9", "Zm9v!"]
  i = 0
  while i < invalid_url.size
    c_hit = false
    w_hit = false
    begin
      Base64.__c_url_decode(invalid_url[i])
    rescue e
      c_hit = true
    begin
      Base64.url_decode(invalid_url[i])
    rescue e
      w_hit = true
    check("invalid.url.c.[i]", c_hit, true)
    check("invalid.url.w.[i]", w_hit, true)
    checked += 2
    i += 1

  # Intentional correction: old C used strlen and truncated length-counted
  # Strings at NUL. The source implementation preserves all stored bytes.
  nul = u8[3]
  nul[0] = 65
  nul[1] = 0
  nul[2] = 66
  nul_text = ccall("w_string_from_byte_array", nul)
  check("old C embedded NUL", Base64.__c_encode(nul_text), "QQ==")
  check("W embedded NUL", Base64.encode(nul_text), "QQBC")

  encoded_nul = u8[5]
  encoded_nul[0] = 90
  encoded_nul[1] = 103
  encoded_nul[2] = 0
  encoded_nul[3] = 61
  encoded_nul[4] = 61
  encoded_nul_text = ccall("w_string_from_byte_array", encoded_nul)
  expected_f = u8[1]
  expected_f[0] = 102
  check_bytes("old C encoded NUL truncation", Base64.__c_decode(encoded_nul_text), expected_f)
  nul_decode_hit = false
  begin
    Base64.decode(encoded_nul_text)
  rescue e
    nul_decode_hit = true
  check("W encoded NUL invalid", nul_decode_hit, true)
  checked += 4

  << "correctness: ok ([checked] exact checks plus documented embedded-NUL correction)"

-> finish_timing(start_s, checksum)
  [clock() - start_s, checksum]

-> encoded_checksum(output)
  n = output.size ## i64
  data = ccall_nobox("w_string_byte_ptr", output) ## i64
  n * 257 + raw_load_u8(data, 0) * 17 + raw_load_u8(data, n - 1)

-> decoded_checksum(output)
  n = output.size ## i64
  n * 257 + output[0] * 17 + output[n - 1]

-> time_encode_c(input, iters)
  checksum = 0
  i = 0
  start_s = clock()
  while i < iters
    checksum += encoded_checksum(Base64.__c_encode(input))
    i += 1
  finish_timing(start_s, checksum)

-> time_encode_w(input, iters)
  checksum = 0
  i = 0
  start_s = clock()
  while i < iters
    checksum += encoded_checksum(Base64.encode(input))
    i += 1
  finish_timing(start_s, checksum)

-> time_decode_c(input, iters)
  checksum = 0
  i = 0
  start_s = clock()
  while i < iters
    checksum += decoded_checksum(Base64.__c_decode(input))
    i += 1
  finish_timing(start_s, checksum)

-> time_decode_w(input, iters)
  checksum = 0
  i = 0
  start_s = clock()
  while i < iters
    checksum += decoded_checksum(Base64.decode(input))
    i += 1
  finish_timing(start_s, checksum)

-> time_url_encode_c(input, iters)
  checksum = 0
  i = 0
  start_s = clock()
  while i < iters
    checksum += encoded_checksum(Base64.__c_url_encode(input))
    i += 1
  finish_timing(start_s, checksum)

-> time_url_encode_w(input, iters)
  checksum = 0
  i = 0
  start_s = clock()
  while i < iters
    checksum += encoded_checksum(Base64.url_encode(input))
    i += 1
  finish_timing(start_s, checksum)

-> time_url_decode_c(input, iters)
  checksum = 0
  i = 0
  start_s = clock()
  while i < iters
    checksum += decoded_checksum(Base64.__c_url_decode(input))
    i += 1
  finish_timing(start_s, checksum)

-> time_url_decode_w(input, iters)
  checksum = 0
  i = 0
  start_s = clock()
  while i < iters
    checksum += decoded_checksum(Base64.url_decode(input))
    i += 1
  finish_timing(start_s, checksum)

-> emit_pair(name, c_result, w_result, iters, emit)
  if c_result[1] != w_result[1]
    fail_check("benchmark checksum [name]", "C=[c_result[1]] W=[w_result[1]]")
  if emit
    c_ns = c_result[0] * 1_000_000_000 / iters
    w_ns = w_result[0] * 1_000_000_000 / iters
    ratio = w_result[0] / c_result[0]
    << "RESULT|[name]|[c_ns]|[w_ns]|[ratio]|[c_result[1]]"

-> run_pairs(raw, standard_text, url_text, iters, parity, emit = true)
  if parity == 0
    ec = time_encode_c(raw, iters)
    ew = time_encode_w(raw, iters)
    dc = time_decode_c(standard_text, iters)
    dw = time_decode_w(standard_text, iters)
    uec = time_url_encode_c(raw, iters)
    uew = time_url_encode_w(raw, iters)
    udc = time_url_decode_c(url_text, iters)
    udw = time_url_decode_w(url_text, iters)
  else
    ew = time_encode_w(raw, iters)
    ec = time_encode_c(raw, iters)
    dw = time_decode_w(standard_text, iters)
    dc = time_decode_c(standard_text, iters)
    uew = time_url_encode_w(raw, iters)
    uec = time_url_encode_c(raw, iters)
    udw = time_url_decode_w(url_text, iters)
    udc = time_url_decode_c(url_text, iters)

  emit_pair("encode", ec, ew, iters, emit)
  emit_pair("decode", dc, dw, iters, emit)
  emit_pair("url_encode", uec, uew, iters, emit)
  emit_pair("url_decode", udc, udw, iters, emit)

args = argv()
mode = args.size > 0 ? args[0] : "bench"
if mode == "check"
  run_correctness()
  exit(0)

iters = DEFAULT_ITERS
if args.size > 1
  iters = args[1].to_i
if iters <= 0
  << "iterations must be positive"
  exit(2)

parity = args.size > 2 ? args[2].to_i : 0
if parity != 0 && parity != 1
  << "sample parity must be 0 or 1"
  exit(2)

raw = deterministic_bytes(1024, 31)
standard_text = Base64.__c_encode(raw)
url_text = Base64.__c_url_encode(raw)
run_pairs(raw, standard_text, url_text, WARMUP_ITERS, parity, false)
run_pairs(raw, standard_text, url_text, iters, parity, true)
