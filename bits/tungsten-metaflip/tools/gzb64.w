# gzb64 - gzip and the Base64 text form of the lineage bundles' tensors
# (`*.mfw.gz.b64`), on top of core/gzip.w.
#
#   gzb64 decode IN.b64 [OUT]                 Base64 text -> gunzip -> the original bytes
#   gzb64 encode IN [OUT [LEVEL [WIDTH]]]     gzip IN -> Base64 text
#   gzb64 gunzip IN.gz [OUT]                  gunzip a raw gzip file
#   gzb64 gzip IN [OUT [LEVEL]]               gzip a file
#
# OUT defaults to standard output, as does "-" in a compiled binary (bin/tungsten
# takes a bare "-" for a flag: name /dev/stdout to give LEVEL without a file).
# An existing OUT file is overwritten.  LEVEL is 0-9 (default 9, the level Python's gzip.compress uses
# for the existing bundles).  WIDTH is the characters per Base64 line, a
# multiple of 4 (default 76, Python's base64.encodebytes; 0 writes one line, the
# other layout found under tools/certificates).  The output is deterministic
# (header mtime 0): the same input and level always give the same bytes.
#
# Corrupt input (bad Base64, a bad gzip stream, a failed CRC or size check)
# exits 1 with the GzipError message on standard error; usage errors and
# unreadable input files exit 2.

-> say(text)
  ccall("w_eputs", text)

-> usage
  say("usage: gzb64 decode IN.b64 \[OUT\]")
  say("       gzb64 encode IN \[OUT \[LEVEL \[WIDTH\]\]\]")
  say("       gzb64 gunzip IN.gz \[OUT\]")
  say("       gzb64 gzip IN \[OUT \[LEVEL\]\]")
  exit(2)

-> die(status, text)
  say("gzb64: " + text)
  exit(status)

# Write the bytes of `data` (a ByteArray or a String) to standard output.
-> write_stdout(data)
  bytes = data.is_a?(String) ? ccall("w_string_bytes_view", data) : data
  ptr = ccall_nobox("w_u8_live_data_ptr", bytes) ## i64
  total = bytes.size ## i64
  done = 0 ## i64
  while done < total
    sent = ccall_nobox("write", 1, ptr + done, total - done) ## i64
    die(1, "cannot write standard output") if sent <= 0
    done += sent

-> emit(data, path)
  if path == "-"
    write_stdout(data)
  elsif data.is_a?(String)
    die(1, "cannot write " + path) if !write_file(path, data)
  else
    die(1, "cannot write " + path) if !write_file_bytes(path, data)

# A numeric argument: decimal digits only.
-> number(text)
  usage if text.size == 0
  n = 0
  i = 0
  while i < text.size
    digit = "0123456789".index(text.slice(i, 1))
    usage if digit == nil
    n = n * 10 + digit
    i += 1
  n

args = argv()
usage if args.size < 2 || args.size > 5
mode = args[0]
source = args[1]
target = args.size > 2 ? args[2] : "-"
level = args.size > 3 ? number(args[3]) : 9
width = args.size > 4 ? number(args[4]) : 76
usage if mode != "decode" && mode != "encode" && mode != "gunzip" && mode != "gzip"
usage if args.size > 3 && mode != "encode" && mode != "gzip"
usage if args.size > 4 && mode != "encode"
usage if level > 9 || width % 4 != 0

input = mode == "decode" ? read_file(source) : read_file_bytes(source)
die(2, "cannot read " + source) if input == nil

result = nil
begin
  if mode == "decode"
    result = Gzip.decode_b64(input)
  elsif mode == "gunzip"
    result = Gzip.decompress(input)
  elsif mode == "encode"
    result = Gzip.encode_b64(input, level, width)
  else
    result = Gzip.compress(input, level)
rescue e: GzipError
  die(1, source + ": " + e.message)
emit(result, target)
