# File.read / File.read_bytes on a missing path raise FileNotFound instead
# of answering nil (which used to surface later as a confusing error at the
# first use of the result, e.g. "Crypto digest: expected String or ByteArray").
#
# Run: `bin/tungsten -o /tmp/frm spec/core/file_read_missing_spec.w && /tmp/frm`

-> check(name, got, want)
  if got.to_s() == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want
    exit 1

missing = "/nonexistent/tungsten-file-read-missing-spec"
outcome = "none"
begin
  File.read(missing)
  outcome = "returned"
rescue e: FileNotFound
  outcome = "file_not_found"
check("read.missing_raises", outcome, "file_not_found")

outcome = "none"
begin
  File.read_bytes(missing)
  outcome = "returned"
rescue e: FileNotFound
  outcome = "file_not_found"
check("read_bytes.missing_raises", outcome, "file_not_found")

outcome = "none"
begin
  File.binread(missing)
  outcome = "returned"
rescue e: IOError
  outcome = "io_error"
check("binread.missing_is_io_error", outcome, "io_error")

tempfile = Tempfile.new("tungsten-file-read-missing")
tempfile.write("bytes")
check("read.present", File.read(tempfile.path), "bytes")
check("read_bytes.present", File.read_bytes(tempfile.path).size, "5")
check("exist.missing", File.exist?(missing), "false")
