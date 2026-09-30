# core/gzip.w and tools/gzb64.w on the bit's own data.
#
# 1. Every committed certificate (tools/certificates/**/*.mfw.gz.b64, written by
#    Python's gzip + base64) decodes: the gzip trailer's CRC-32 and size checks
#    inside Gzip.decode_b64_text vouch for the bytes, and the text must be a
#    well-formed MFW1 tensor whose header rank equals its number of term lines.
# 2. The gzb64 command line tool decodes, encodes, gzips and gunzips through
#    files and standard output, and reports bad input with exit status 1 (2 for
#    unreadable files and usage errors).
# 3. What the Tungsten compressor writes is accepted by independent decoders:
#    the system gzip (-t and -dc) and Python (gzip + strict base64), when they
#    are installed.
#
# The tool runs through $TUNGSTEN (default: bin/tungsten of this checkout).
use core/system

failures = 0 ## i64

-> expect(label, condition) i64
  if !condition
    << "FAIL " + label
    return 1
  0

-> quote(text)
  "'" + text.replace("'", "'\\''") + "'"

root = file_expand_path(__DIR__ + "/..")
tungsten = env("TUNGSTEN")
if tungsten == nil || tungsten == ""
  tungsten = file_expand_path(root + "/../../bin/tungsten")
tool = quote(tungsten) + " " + quote(root + "/tools/gzb64.w")
tmp = env("TMPDIR")
if tmp == nil || tmp == ""
  tmp = "/tmp"
scratch = capture("mktemp -d " + quote(tmp + "/metaflip-gzip-XXXXXX")).strip()
if scratch == ""
  << "FAIL cannot create scratch directory"
  exit(1)

# ---- 1. the committed certificates ------------------------------------------
paths = capture("find " + quote(root + "/tools/certificates") + " -name '*.mfw.gz.b64' | sort").split("\n")
decoded = 0 ## i64
total_rank = 0 ## i64
malformed = 0 ## i64
corrupt = 0 ## i64
i = 0 ## i64
while i < paths.size
  path = paths[i]
  i += 1
  if path.size > 0
    begin
      text = Gzip.decode_b64_text(read_file(path))
      lines = text.split("\n")
      header = lines[0].split(" ")
      rank = header.size == 5 && header[0] == "MFW1" ? header[4].to_i : -1
      if rank > 0 && lines.size == rank + 2 && lines.last == "" && text.ends_with?("\n")
        decoded += 1
        total_rank += rank
      else
        malformed += 1
        << "FAIL not a well-formed MFW1 tensor: " + path
    rescue e: GzipError
      corrupt += 1
      << "FAIL " + path + ": " + e.message
failures += expect("all " + paths.size.to_s + " committed certificates decode", corrupt == 0 && malformed == 0 && decoded > 300)

# ---- 2. the command line tool -----------------------------------------------
sample = root + "/tools/certificates/block47-exact-20260923/20x23x31-r7636.mfw.gz.b64"
plain = scratch + "/tensor.mfw"
via_tool = scratch + "/via-tool.mfw"
encoded = scratch + "/tensor.mfw.gz.b64"
again = scratch + "/again.mfw"
z = write_file(plain, Gzip.decode_b64_text(read_file(sample)))
failures += expect("gzb64 decode writes a file", system(tool + " decode " + quote(sample) + " " + quote(via_tool)))
failures += expect("the tool decodes like the library", read_file(via_tool) == read_file(plain))
failures += expect("gzb64 decode writes standard output", capture(tool + " decode " + quote(sample)) == read_file(plain))
failures += expect("gzb64 encode writes a file", system(tool + " encode " + quote(plain) + " " + quote(encoded)))
text = read_file(encoded)
failures += expect("the encoded file is 76 columns with a final newline", text.ends_with?("\n") && text.split("\n")[0].size == 76)
failures += expect("it starts like the bundle files", text.starts_with?("H4sIAAAAAAAC/"))
failures += expect("gzb64 decode reads it back", system(tool + " decode " + quote(encoded) + " " + quote(again)) && read_file(again) == read_file(plain))
failures += expect("encoding twice gives the same bytes", capture(tool + " encode " + quote(plain) + " /dev/stdout") == text)
one_line = capture(tool + " encode " + quote(plain) + " /dev/stdout 9 0")
failures += expect("width 0 writes one line", one_line.split("\n").size == 2 && one_line.replace("\n", "") == text.replace("\n", ""))
raw_gz = scratch + "/tensor.gz"
failures += expect("gzb64 gzip", system(tool + " gzip " + quote(plain) + " " + quote(raw_gz) + " 6"))
failures += expect("gzb64 gunzip", capture(tool + " gunzip " + quote(raw_gz)) == read_file(plain))
failures += expect("a missing input exits 2", capture(tool + " decode " + quote(scratch + "/absent") + " 2>/dev/null; echo status=$?").ends_with?("status=2\n"))
failures += expect("a bad Base64 file exits 1", capture(tool + " decode " + quote(plain) + " 2>&1; echo status=$?").ends_with?("status=1\n"))
failures += expect("the error names the file and the reason",
                   capture(tool + " gunzip " + quote(plain) + " 2>&1").include?("gzip: not a gzip stream"))
failures += expect("usage errors exit 2", capture(tool + " 2>/dev/null; echo status=$?").ends_with?("status=2\n"))
failures += expect("a level above 9 exits 2", capture(tool + " gzip " + quote(plain) + " /dev/stdout 12 2>/dev/null; echo status=$?").ends_with?("status=2\n"))

# ---- 3. independent decoders accept what Tungsten writes ------------------------
if capture("command -v gzip").strip() != ""
  failures += expect("system gzip -t accepts the output", system("gzip -t " + quote(raw_gz)))
  failures += expect("system gzip -dc gives the tensor back", capture("gzip -dc " + quote(raw_gz)) == read_file(plain))
python = capture("command -v python3").strip()
if python != ""
  check = "import base64, gzip, sys; text = open(sys.argv\[1\], 'rb').read(); " + "raw = gzip.decompress(base64.b64decode(text.replace(b'\\n', b''), validate=True)); " + "sys.exit(0 if raw == open(sys.argv\[2\], 'rb').read() else 1)"
  failures += expect("Python decodes the .gz.b64 written by gzb64 (strict Base64)", system(quote(python) + " -c " + quote(check) + " " + quote(encoded) + " " + quote(plain)))
  z = write_file(scratch + "/one-line.b64", one_line)
  failures += expect("Python reads the width 0 layout too", system(quote(python) + " -c " + quote(check) + " " + quote(scratch + "/one-line.b64") + " " + quote(plain)))

z = system("rm -rf " + quote(scratch))
if failures > 0
  << "metaflip gzip: " + failures.to_s + " failure(s)"
  exit(1)
<< "metaflip gzip: ok (" + decoded.to_s + " certificates, total rank " + total_rank.to_s + ")"
