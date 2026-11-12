# Gzip (core/gzip.w): gzip / DEFLATE decompression and compression, and the
# Base64 text form of the .gz.b64 files.
#
# Golden inputs live in spec/fixtures/gzip/ and were made by Python's zlib
# (make_fixtures.py there): stored, fixed-Huffman and dynamic-Huffman blocks,
# every optional gzip header field, multi-member streams, a real GF(2) tensor
# in both .gz.b64 layouts.  Corrupt inputs are made by mutating those fixtures
# or hand-assembled from bits (the streams zlib itself rejects).  The
# compressor is checked by round trips, by header/size properties and by a
# pinned digest of its (deterministic) output; that its output is accepted by
# an independent inflater is checked by the metaflip gzb64 test against Python.
#
# spec: compiled -- interpreted, inflating one 20 KB fixture holds ~850 MB that is never reclaimed; the run exceeds the 8 GiB memory limit
#
# Run from the repository root:
#   bin/tungsten spec/core/gzip_spec.w
#   bin/tungsten -o /tmp/gzip-spec spec/core/gzip_spec.w && /tmp/gzip-spec

use core/digest

passed = Atomic.new(0)

-> check(name, condition)
  if !condition
    << "FAIL " + name
    exit 1
  passed.increment()
  << "PASS " + name

-> fixture(name)
  read_file_bytes(__DIR__ + "/../fixtures/gzip/" + name)

-> u8_from(list)
  out = u8[list.size]
  i = 0
  while i < list.size
    out[i] = list[i]
    i += 1
  out

-> same_bytes(a, b)
  return false if a.size != b.size
  i = 0
  while i < a.size
    return false if a[i] != b[i]
    i += 1
  true

-> concat(a, b)
  out = u8[a.size + b.size]
  i = 0
  while i < a.size
    out[i] = a[i]
    i += 1
  j = 0
  while j < b.size
    out[a.size + j] = b[j]
    j += 1
  out

# The first n bytes of bytes.
-> head(bytes, n)
  out = u8[n]
  i = 0
  while i < n
    out[i] = bytes[i]
    i += 1
  out

# bytes with byte i replaced.
-> with_byte(bytes, i, value)
  out = head(bytes, bytes.size)
  out[i] = value
  out

# Deterministic bytes: a linear congruential generator, masked to an alphabet.
-> lcg_bytes(n, seed, mask) (i64 i64 i64) u8[]
  out = u8[n]
  x = seed ## i64
  i = 0 ## i64
  while i < n
    x = (x * 1103515245 + 12345) & 0x7FFFFFFF
    out[i] = (x >> 16) & mask
    i += 1
  out

-> periodic(n, period) (i64 i64) u8[]
  out = u8[n]
  i = 0 ## i64
  while i < n
    out[i] = 65 + (i * 7) % period
    i += 1
  out

# The GzipError code raised by decompressing bytes, :ok when it succeeds.
-> outcome(bytes)
  code = :ok
  begin
    Gzip.decompress(bytes)
  rescue e: GzipError
    code = e.code
  code

-> b64_outcome(text)
  code = :ok
  begin
    Gzip.decode_b64(text)
  rescue e: GzipError
    code = e.code
  code

# Does the operation named by `op` raise ArgumentError for these arguments?
-> argument_error?(op, a, b)
  raised = false
  begin
    if op == 1
      Gzip.compress(a, b)
    elsif op == 2
      Gzip.decompress(a)
    else
      Gzip.encode_b64(a, 6, b)
  rescue e: ArgumentError
    raised = true
  raised

# A gzip member around a hand-made DEFLATE stream (the trailer is never read
# for the streams below: they fail first).
-> wrap(deflated)
  header = u8_from([0x1F, 0x8B, 8, 0, 0, 0, 0, 0, 0, 255])
  concat(concat(header, u8_from(deflated)), u8[8])

# The type of the first DEFLATE block of a member without optional header
# fields: 0 stored, 1 fixed Huffman, 2 dynamic Huffman.
-> first_block_type(bytes)
  (bytes[10] >> 1) & 3

sample = fixture("sample.txt")
noise = fixture("random.raw")
tensor = fixture("tensor.mfw")
mib_of_zeros = u8[1048576]

# ---- decompressing zlib's streams ------------------------------------------
rows = read_file(__DIR__ + "/../fixtures/gzip/manifest.tsv").split("\n")
listed = 0
i = 0
while i < rows.size
  if rows[i].size > 0
    fields = rows[i].split("\t")
    packed = fixture(fields[0])
    want = fields[1] == "-" ? mib_of_zeros : fixture(fields[1])
    check("decompress " + fields[0], same_bytes(Gzip.decompress(packed), want))
    check("decompress_text " + fields[0], Gzip.decompress_text(packed) == ccall("w_string_from_byte_array", want))
    listed += 1
  i += 1
check("manifest lists the fixtures", listed == 17)

check("stored blocks (level 0)", first_block_type(fixture("sample.l0.gz")) == 0)
check("fixed-Huffman blocks (Z_FIXED)", first_block_type(fixture("sample.fixed.gz")) == 1)
check("dynamic-Huffman blocks (level 6)", first_block_type(fixture("sample.l6.gz")) == 2)
check("dynamic-Huffman blocks (Z_HUFFMAN_ONLY)", first_block_type(fixture("sample.huffman.gz")) == 2)
check("incompressible data is stored by zlib", first_block_type(fixture("random.gz")) == 0)

check("a String is accepted as input", same_bytes(Gzip.decompress(read_file(__DIR__ + "/../fixtures/gzip/sample.l9.gz")), sample))
check("empty input", Gzip.decompress(u8[0]).size == 0)
check("empty String", Gzip.decompress("").size == 0)
check("an empty member", Gzip.decompress(u8_from([0x1F, 0x8B, 8, 0, 0, 0, 0, 0, 0, 3, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0])).size == 0)

# ---- members -------------------------------------------------------------------
multi = fixture("multi.gz")
first_only = head(multi, 33)
check("two members", Gzip.decompress_text(multi) == "first member\nsecond member\n")
check("one member of the two", Gzip.decompress_text(first_only) == "first member\n")
check("zero padding after a member", Gzip.decompress_text(concat(first_only, u8[5])) == "first member\n")
big_then_small = concat(Gzip.compress(mib_of_zeros, 6), Gzip.compress(sample, 6))
check("a member the last one's size does not predict", Gzip.decompress(big_then_small).size == 1048576 + 64000)

# ---- corrupt streams ---------------------------------------------------------
good = fixture("sample.l6.gz")
n = good.size
check("intact fixture", outcome(good) == :ok)
check("not gzip", outcome("hello, this is not gzip") == :not_gzip)
check("magic only", outcome(u8_from([0x1F, 0x8B, 8])) == :truncated)
check("one byte", outcome(u8_from([0x1F])) == :truncated)
check("unknown method", outcome(with_byte(good, 2, 7)) == :bad_method)
check("reserved flag", outcome(with_byte(good, 3, 0x20)) == :bad_flags)
check("header crc", outcome(with_byte(fixture("header_hcrc.gz"), 10, 0)) == :header_crc)
check("cut inside the FNAME field", outcome(head(fixture("header_fname.gz"), 14)) == :truncated)
check("cut inside the FEXTRA field", outcome(head(fixture("header_extra.gz"), 13)) == :truncated)
check("cut inside the stream", outcome(head(good, n / 2)) == :truncated)
check("cut before the trailer", outcome(head(good, n - 8)) == :truncated)
check("cut inside the trailer", outcome(head(good, n - 3)) == :truncated)
check("crc mismatch", outcome(with_byte(good, n - 8, good[n - 8] ^ 1)) == :crc)
check("size mismatch", outcome(with_byte(good, n - 4, good[n - 4] ^ 1)) == :size)
check("size that is far too large", outcome(with_byte(with_byte(good, n - 1, 255), n - 2, 255)) == :size)
small_size = with_byte(with_byte(with_byte(with_byte(good, n - 1, 0), n - 2, 0), n - 3, 0), n - 4, 9)
check("size that is far too small", outcome(small_size) == :size)
check("garbage after the last member", outcome(concat(good, u8_from([1, 2, 3]))) == :not_gzip)
check("a second member cut short", outcome(head(multi, 50)) == :truncated)

flips = [40, 300, 1000, 5000, 9000, 16000]
flipped = 0
missed = 0
k = 0
while k < flips.size
  bit = 0
  while bit < 8
    flipped += 1
    missed += 1 if outcome(with_byte(good, flips[k], good[flips[k]] ^ (1 << bit))) == :ok
    bit += 1
  k += 1
check("no single-bit corruption goes unnoticed (" + flipped.to_s + " flips)", missed == 0)

check("block type 3", outcome(wrap([7])) == :bad_block)
check("stored block with a wrong NLEN", outcome(wrap([1, 5, 0, 0, 0, 1, 2, 3, 4, 5])) == :bad_stored)
check("distance beyond the start of the output", outcome(wrap([3, 2, 0])) == :bad_distance)
check("over-subscribed code lengths", outcome(wrap([5, 0, 146, 4])) == :bad_huffman)
check("repeat with no previous length", outcome(wrap([5, 0, 2, 36])) == :bad_huffman)
check("distance symbol 30", outcome(wrap([75, 4, 62, 0])) == :bad_code)
check("length symbol 286", outcome(wrap([75, 28, 3, 0])) == :bad_code)

message = ""
begin
  Gzip.decompress("nope")
rescue e: ParseError
  message = e.message
check("a GzipError is a ParseError with a readable message", message == "gzip: not a gzip stream")

# ---- compressing -------------------------------------------------------------
-> round_trip?(data, level)
  packed = Gzip.compress(data, level)
  same_bytes(Gzip.decompress(packed), data) && same_bytes(packed, Gzip.compress(data, level))

# Round trips at every level in `levels`; returns the failing level, or -1.
-> first_failing_level(data, levels)
  j = 0
  while j < levels.size
    return levels[j] if !round_trip?(data, levels[j])
    j += 1
  -1

names = ["empty", "one byte", "two bytes", "three bytes", "258 zeros", "259 zeros", "periodic 3", "periodic 700",
         "a 4-letter alphabet", "noise", "sample text", "real tensor", "random fixture", "a MiB of zeros"]
inputs = [u8[0], u8_from([120]), u8_from([1, 1]), u8_from([7, 8, 9]), u8[258], u8[259], periodic(3000, 3),
          periodic(90000, 700), lcg_bytes(40000, 5, 3), lcg_bytes(70000, 9, 255), sample, tensor, noise, mib_of_zeros]
i = 0
while i < inputs.size
  check("round trip, levels 0-9: " + names[i], first_failing_level(inputs[i], [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]) == -1)
  i += 1

sizes = [32767, 32768, 32769, 65535, 65536, 65537, 131071, 200000]
i = 0
while i < sizes.size
  check("round trip around a block boundary: " + sizes[i].to_s + " bytes", first_failing_level(lcg_bytes(sizes[i], sizes[i], 15), [1, 6, 9]) == -1)
  i += 1

size1 = Gzip.compress(sample, 1).size
size6 = Gzip.compress(sample, 6).size
size9 = Gzip.compress(sample, 9).size
check("level 6 is within 3% of zlib's size", size6 * 100 <= fixture("sample.l6.gz").size * 103)
check("level 9 is within 3% of zlib's size", size9 * 100 <= fixture("sample.l9.gz").size * 103)
check("level 1 is within 30% of zlib's size", size1 * 100 <= fixture("sample.l1.gz").size * 130)
check("level 9 beats level 6 beats level 1", size9 <= size6 && size6 < size1)
check("a MiB of zeros packs to under 2 KiB", Gzip.compress(mib_of_zeros, 6).size < 2048)
check("noise grows by under 0.1%", Gzip.compress(noise, 6).size < noise.size + noise.size / 1000 + 64)
check("level 0 stores", Gzip.compress(sample, 0).size == 64000 + 18 + 5)
text = "héllo wörld " * 50
check("a String compresses like its bytes", same_bytes(Gzip.compress(text, 6), Gzip.compress(ccall("w_string_bytes_view", text), 6)))
check("and decompresses to itself", Gzip.decompress_text(Gzip.compress(text, 6)) == text)

# The header: magic, deflate, no flags, mtime 0, XFL by level, OS unknown.
-> header_of(level)
  head(Gzip.compress(sample, level), 10)
check("header at level 6", same_bytes(header_of(6), u8_from([0x1F, 0x8B, 8, 0, 0, 0, 0, 0, 0, 255])))
check("header at level 9", header_of(9)[8] == 2)
check("header at level 1", header_of(1)[8] == 4)
check("header at level 0", header_of(0)[8] == 4)
packed = Gzip.compress(sample, 6)
crc = Crypto:CRC32.checksum(sample)
tail = packed.size - 8
check("trailer holds the crc", packed[tail] == (crc & 255) && packed[tail + 3] == (crc >> 24))
check("trailer holds the size", packed[tail + 4] == (64000 & 255) && packed[tail + 5] == (64000 >> 8))

# Pinned digests catch any change of the compressor's output.
check("pinned output at level 6", Digest.sha256(Gzip.compress(sample, 6)) == "a8892d3149a75b7bcd1b614d686beb4c69ea44d4b2ca54a80ee382c389046196")
check("pinned output at level 9", Digest.sha256(Gzip.compress(sample, 9)) == "1aa61eb08608e8361545065cc4ebf9e9ca8e608030f6d201e211d65a670bf489")
check("pinned output at level 1", Digest.sha256(Gzip.compress(sample, 1)) == "ebde620d44e9b52adfaccd318dfe5d6832005756ed0cd9977da21ecf9ea4e35e")

# ---- argument errors -----------------------------------------------------------
check("compress rejects a number", argument_error?(1, 42, 6))
check("compress rejects nil", argument_error?(1, nil, 6))
check("decompress rejects nil", argument_error?(2, nil, 0))
check("level above 9", argument_error?(1, "x", 10))
check("negative level", argument_error?(1, "x", -1))
check("level that is not a number", argument_error?(1, "x", "6"))
check("odd line width", argument_error?(3, "x", 10))
check("negative line width", argument_error?(3, "x", -4))
check("valid arguments are accepted", !argument_error?(1, "x", 6) && !argument_error?(3, "x", 0))

# ---- Base64 text -----------------------------------------------------------------
book = read_file(__DIR__ + "/../fixtures/gzip/tensor.book.gz.b64")
line = read_file(__DIR__ + "/../fixtures/gzip/tensor.line.gz.b64")
check("decode_b64, 76-column layout", same_bytes(Gzip.decode_b64(book), tensor))
check("decode_b64, one-line layout", same_bytes(Gzip.decode_b64(line), tensor))
check("decode_b64_text", Gzip.decode_b64_text(book) == read_file(__DIR__ + "/../fixtures/gzip/tensor.mfw"))
check("decode_b64 of a ByteArray", same_bytes(Gzip.decode_b64(fixture("tensor.book.gz.b64")), tensor))
check("decode_b64 without the final newline", same_bytes(Gzip.decode_b64(book.slice(0, book.size - 1)), tensor))
check("empty Base64 text", Gzip.decode_b64("").size == 0)

encoded = Gzip.encode_b64(tensor, 9)
lines = encoded.split("\n")
check("encode_b64 ends with a newline", encoded.ends_with?("\n") && lines.last == "")
check("encode_b64 wraps at 76", lines.size > 2 && lines[0].size == 76 && lines[lines.size - 2].size <= 76)
check("encode_b64 starts like the .gz.b64 files", encoded.starts_with?("H4sIAAAAAAAC/"))
check("encode_b64 round trip", same_bytes(Gzip.decode_b64(encoded), tensor))
check("encode_b64 is deterministic", encoded == Gzip.encode_b64(tensor, 9))
oneline = Gzip.encode_b64(tensor, 9, 0)
check("width 0 gives one line", oneline.split("\n").size == 2 && oneline.ends_with?("\n"))
check("width 0 has the same characters", oneline.replace("\n", "") == encoded.replace("\n", ""))
check("width 64", Gzip.encode_b64(sample, 6, 64).split("\n")[0].size == 64)

sizes = [0, 1, 2, 3, 4, 5, 10, 57, 58, 59]
padded = 0
i = 0
while i < sizes.size
  bytes = lcg_bytes(sizes[i], 3, 255)
  padded += 1 if same_bytes(Gzip.decode_b64(Gzip.encode_b64(bytes, 6)), bytes)
  i += 1
check("every padding length round trips", padded == sizes.size)
check("newlines anywhere are ignored", same_bytes(Gzip.decode_b64("\n" + encoded.replace("\n", "\n\n") + "\n"), tensor))

plain = oneline.replace("\n", "")
check("a bad character", b64_outcome(plain.replace("H4sI", "H4s!")) == :base64)
check("CRLF line ends are not accepted", b64_outcome(encoded.replace("\n", "\r\n")) == :base64)
check("a space", b64_outcome(" " + plain) == :base64)
check("cut to a partial group", b64_outcome(plain.slice(0, plain.size - 1)) == :base64)
check("padding in the middle", b64_outcome("H4sI=AAA" + plain.slice(8, plain.size - 8)) == :base64)
check("three padding characters", b64_outcome("H4s===") == :base64)
check("valid Base64 that is not gzip", b64_outcome("aGVsbG8gd29ybGQh") == :not_gzip)
check("valid Base64 of a truncated stream", b64_outcome("H4sIAAAAAAAAA6urAQAA") == :truncated)

<< "gzip_spec: " + passed.load.to_s + " checks passed"
