# Golden tests of tools/verify_tensor.w and lib/metaflip/gf2/tensor_verifier.w.
#
# The expectations come from the Ruby original, tools/verify_tensor.rb: for
# every fixture of spec/fixtures/gf2_scheme/ (cases.tsv, made by generate.py)
# the Tungsten port must give the same exit status, the same record and the
# same failure message as Ruby, under each of the three gates; --strict must
# give the verdict of the Python read_blob + exact. The option parser, the
# JSON layout and the shape inference are checked against transcripts of the
# Ruby tool. Prints FAIL lines and exits 1 on any failure, else PASS.
#
# The last block runs the tool as a separate process (needs a working
# toolchain: $TUNGSTEN, or bin/tungsten of the repository root).
use ../lib/metaflip/gf2/tensor_verifier

fixtures = __DIR__ + "/fixtures/gf2_scheme"
failures = 0

-> same(label, got, want)
  if got == want
    return 0
  << "FAIL " + label
  << "  got:  " + got.to_s.slice(0, 300)
  << "  want: " + want.to_s.slice(0, 300)
  1

-> check(label, ok)
  if ok
    return 0
  << "FAIL " + label
  1

-> table(name)
  rows = []
  read_file(__DIR__ + "/fixtures/gf2_scheme/" + name).split("\n").each -> (line)
    if line != "" && !line.starts_with?("#")
      rows.push(line.split("\t"))
  rows

-> run(args)
  Metaflip:Gf2:TensorVerifier.main(args)

-> expand(path)
  Metaflip:Gf2:TensorVerifier.expand_path(path)

# The body of one record as JSON.pretty_generate prints it (without the array brackets).
-> record_body(shape, rank, density, sha256, path)
  "  {\n    \"exact\": true,\n    \"shape\": \"[shape]\",\n    \"rank\": [rank],\n    \"density\": [density],\n    \"sha256\": \"[sha256]\",\n    \"path\": \"[path]\"\n  }\n"

-> record_json(shape, rank, density, sha256, path)
  "\[\n" + record_body(shape, rank, density, sha256, path) + "\]\n"

# The array JSON.pretty_generate prints for several record bodies.
-> array_json(bodies)
  out = "\[\n"
  bodies.each_with_index -> (body, i)
    out = out + (i + 1 < bodies.size ? body.slice(0, body.size - 1) + ",\n" : body)
  out + "\]\n"

-> failure_line(message)
  "Tensor verification failed: " + message + "\n"

rows_for_scheme_test = "12 1 12\n1 10 10\n8 5 5\n3 8 3\n5 3 8\n10 12 1\n"

# verify_text / read as a value: the record, or the failure message.
-> outcome(text, n, m, p)
  begin
    Metaflip:Gf2:TensorVerifier.verify_text(text, n, m, p, :both, false)
  rescue e
    "[e]"

# read_scheme as a value: "N terms", or the failure message.
-> scheme_outcome(text)
  begin
    "[Metaflip:Gf2:TensorVerifier.read_scheme(text, 2, 2, 2).rank] terms"
  rescue e
    "[e]"

# ---- every fixture, all gates, both rule sets ----------------------------------
table("cases.tsv").each -> (row)
  file = row[0]
  path = fixtures + "/" + file
  shape = row[1]
  ruby_ok = row[3] == "0"
  python_ok = row[4] == "0"
  expected_ok = record_json(shape, row[5], row[6], row[7], expand(path))
  ["dense", "sparse", "both"].each -> (gate)
    got = run(["--gate", gate, "--shape", shape, path])
    label = file + " --gate " + gate
    if ruby_ok
      failures += same(label, got, [0, expected_ok, ""])
    else
      failures += same(label, got, [1, "", failure_line(row[5].gsub("@FIXTURES@", fixtures))])
  strict = run(["--strict", "--shape", shape, path])
  if python_ok
    failures += same(file + " --strict", strict, [0, expected_ok, ""])
    failures += same(file + " --strict, shape from the header", run(["--strict", path]), strict)
  else
    failures += same(file + " --strict status", strict[0], 1)
    failures += check(file + " --strict says why", strict[1] == "" && strict[2].starts_with?("Tensor verification failed: "))

# ---- the option parser, as verify_tensor.rb ----------------------------------------------
strassen = fixtures + "/strassen_2x2x2.mfw"
rank23 = fixtures + "/rank23_3x3x3.mfw"
usage = run(["--help"])
failures += same("--help status", usage[0], 0)
failures += check("--help text", usage[1].starts_with?("Usage: verify_tensor.w \[--shape NxMxP\]") && usage[1].index("--shape SHAPE") != nil && usage[2] == "")
failures += same("-h is --help", run(["-h"]), usage)
failures += same("--version", run(["--version"]), [1, "", "verify_tensor.w: version unknown\n"])
failures += same("-v is --version", run(["-v"]), [1, "", "verify_tensor.w: version unknown\n"])
failures += same("no arguments", run([]), [1, "", failure_line("provide at least one certificate")])
failures += same("only --shape", run(["--shape", "2x2x2"]), [1, "", failure_line("provide at least one certificate")])
failures += same("--shape without value", run(["--shape"]), [1, "", failure_line("missing argument: --shape")])
failures += same("unknown option", run(["--bogus", "x"]), [1, "", failure_line("invalid option: --bogus")])
failures += same("unknown short option", run(["-x"]), [1, "", failure_line("invalid option: -x")])
failures += same("bad shape", run(["--shape", "2x2", strassen]), [1, "", failure_line("expected shape NxMxP")])
failures += same("bad shape, zero", run(["--shape", "2x0x2", strassen]), [1, "", failure_line("expected shape NxMxP")])
failures += same("bad shape, leading zero", run(["--shape=02x2x2", strassen]), [1, "", failure_line("expected shape NxMxP")])
failures += same("bad shape comes before missing certificates", run(["--shape", "junk"]), [1, "", failure_line("expected shape NxMxP")])
failures += same("no shape in the path", run([strassen]), [1, "", failure_line("cannot infer shape for " + strassen + "; pass --shape NxMxP")])
failures += same("-- ends the options", run(["--", "-weird"]), [1, "", failure_line("cannot infer shape for -weird; pass --shape NxMxP")])
failures += same("- is a certificate", run(["-"]), [1, "", failure_line("cannot infer shape for -; pass --shape NxMxP")])
failures += same("missing file", run(["--shape", "2x2x2", "/nonexistent/foo.mfw"]), [1, "", failure_line("No such file or directory @ rb_sysopen - /nonexistent/foo.mfw")])
failures += same("missing file, shape from the path", run(["/nonexistent/2x2x2/foo.mfw"]), [1, "", failure_line("No such file or directory @ rb_sysopen - /nonexistent/2x2x2/foo.mfw")])
failures += same("--shape=VALUE", run(["--shape=2x2x2", strassen])[0], 0)
failures += same("--sh=VALUE (a unique prefix)", run(["--sh=2x2x2", strassen])[0], 0)
failures += same("a trailing x is dropped, as by String#split", run(["--shape", "2x2x2x", strassen])[0], 0)
failures += same("the last --shape wins", run(["--shape", "3x3x3", "--shape", "2x2x2", strassen])[0], 0)
failures += same("one shape for every certificate", run(["--shape", "2x2x2", strassen, "--shape", "3x3x3", rank23]), [1, "", failure_line("MFW1 shape mismatch")])
failures += same("options may follow certificates", run([strassen, "--shape", "2x2x2"])[0], 0)
failures += same("an ambiguous prefix", run(["--s", strassen]), [1, "", failure_line("ambiguous option: --s")])
failures += same("--gate value", run(["--gate", "third", "--shape", "2x2x2", strassen]), [1, "", failure_line("invalid argument: --gate third")])
failures += same("--gate needs a value", run(["--gate"]), [1, "", failure_line("missing argument: --gate")])
failures += same("--gate=VALUE", run(["--gate=sparse", "--shape=2x2x2", strassen])[0], 0)
failures += same("--gate=VALUE, refused", run(["--gate=nope", "--shape=2x2x2", strassen]), [1, "", failure_line("invalid argument: --gate nope")])
failures += same("a flag takes no value", run(["--strict=1", strassen]), [1, "", failure_line("needless argument: --strict=1")])
failures += same("missing batch list", run(["--batch", "/nonexistent/list.txt"]), [1, "", failure_line("No such file or directory @ rb_sysopen - /nonexistent/list.txt")])

# ---- certificates of any format as a Scheme -------------------------------------------------------
canonical = Metaflip:Gf2:Scheme.parse(read_file(fixtures + "/rank23_3x3x3.mfw"))
from_checkpoint = Metaflip:Gf2:TensorVerifier.read_scheme(read_file(fixtures + "/3x3x3_rank23_checkpoint.txt"), 3, 3, 3)
failures += same("a checkpoint reads as the same terms", from_checkpoint.sorted.blob, canonical.blob)
wide_canonical = Metaflip:Gf2:Scheme.parse(read_file(fixtures + "/wide68_2x4x17.mfw"))
["wide68_2x4x17_R.txt", "wide68_2x4x17_checkpoint.txt", "wide68_2x4x17.mfw"].each -> (name)
  read = Metaflip:Gf2:TensorVerifier.read_scheme(read_file(fixtures + "/" + name), 2, 4, 17)
  failures += same(name + " reads as the same terms (masks wider than 64 bits)", read.sorted.blob, wide_canonical.blob)
failures += same("read_scheme range-checks", scheme_outcome("7\n16 9 9\n" + rows_for_scheme_test), "zero or out-of-bounds factor at term 0")
failures += same("read_scheme reads a good checkpoint", scheme_outcome("7\n9 9 9\n" + rows_for_scheme_test), "7 terms")

# ---- shape inference and path expansion -----------------------------------------------------------
inferred = run([fixtures + "/shape_dir/2x2x2/certificate.mfw"])
failures += same("shape inferred from the directory", inferred, [0, record_json("2x2x2", 7, 36, Digest.sha256(read_file(strassen)), expand(fixtures + "/shape_dir/2x2x2/certificate.mfw")), ""])
failures += same("the deepest shape component wins", Metaflip:Gf2:TensorVerifier.infer_shape("/a/3x3x3/b/2x2x2/c.txt"), "2x2x2")
failures += same("a name that merely contains a shape does not count", Metaflip:Gf2:TensorVerifier.shape_component?("m_2x2x2.txt"), false)
failures += same("a shape component", Metaflip:Gf2:TensorVerifier.shape_component?("28x32x32"), true)
failures += same("a shape with a zero", Metaflip:Gf2:TensorVerifier.shape_component?("2x0x2"), false)
failures += same("a shape with a fourth part", Metaflip:Gf2:TensorVerifier.shape_component?("2x2x2x2"), false)
cwd = file_pwd()
failures += same("expand_path relative", expand("a/../b//./c"), cwd + "/b/c")
failures += same("expand_path absolute", expand("/a/b/../c/"), "/a/c")
failures += same("expand_path above the root", expand("/.."), "/")
failures += same("expand_path home", expand("~/x"), env("HOME") + "/x")

# ---- --batch and --keep-going ---------------------------------------------------------------------
tmp = env("TMPDIR")
tmp = "/tmp" if tmp == nil || tmp == ""
scratch = capture("mktemp -d '" + tmp + "/verify-tensor-test-XXXXXX'").strip
listing = scratch + "/list.txt"
wide = fixtures + "/wide68_2x4x17_R.txt"
write_file(listing, "# a batch\n\n" + strassen + "\t2x2x2\n" + rank23 + "\t3x3x3\r\n" + wide + "\t2x4x17\n")
batch = run(["--batch", listing])
failures += same("batch status", batch[0], 0)
body1 = record_body("2x2x2", 7, 36, Digest.sha256(read_file(strassen)), expand(strassen))
body2 = run(["--shape", "3x3x3", rank23])[1]
body2 = body2.slice(2, body2.size - 4)
body3 = run(["--shape", "2x4x17", wide])[1]
body3 = body3.slice(2, body3.size - 4)
failures += same("batch: the records in order as one JSON array", batch[1], array_json([body1, body2, body3]))
failures += same("batch and positional certificates", run(["--shape", "2x2x2", strassen, "--batch", listing])[1].slice(0, 13), "\[\n  {\n    \"ex")
write_file(listing, strassen + "\t2x2x2\n" + fixtures + "/mutants/strassen_2x2x2__bit_flip_v.mfw\t2x2x2\n" + rank23 + "\t3x3x3\n")
failures += same("batch fails fast like Ruby", run(["--batch", listing]), [1, "", failure_line("inexact GF(2) tensor at coefficients 3,3")])
keep = run(["--batch", listing, "--keep-going"])
failures += same("keep-going status", keep[0], 1)
failures += same("keep-going keeps the good records", keep[1], array_json([body1, body2]))
failures += same("keep-going names the bad one", keep[2], failure_line(fixtures + "/mutants/strassen_2x2x2__bit_flip_v.mfw: inexact GF(2) tensor at coefficients 3,3"))
write_file(listing, strassen + "\n")
failures += same("a batch line without a shape needs one", run(["--batch", listing])[2], failure_line("cannot infer shape for " + strassen + "; pass --shape NxMxP"))
failures += same("--shape supplies it", run(["--batch", listing, "--shape", "2x2x2"])[0], 0)
failures += same("--strict needs no shape", run(["--batch", listing, "--strict"])[0], 0)

# ---- JSON strings ---------------------------------------------------------------------------------------
failures += same("json_string escapes", Metaflip:Gf2:TensorVerifier.json_string("a\"b\\c\td\ne"), "\"a\\\"b\\\\c\\td\\ne\"")
failures += same("json_string passes UTF-8 through", Metaflip:Gf2:TensorVerifier.json_string("café/x"), "\"café/x\"")
failures += same("json_string escapes control characters", Metaflip:Gf2:TensorVerifier.json_string("a" + 1.chr + 31.chr + 127.chr), "\"a\\u0001\\u001f" + 127.chr + "\"")
odd = scratch + "/odd \"q\" \\ back" + 9.chr + "tab.mfw"
write_file(odd, read_file(strassen))
failures += same("a path needing escapes", run(["--shape", "2x2x2", odd])[1].index("\"path\": \"" + expand(scratch) + "/odd \\\"q\\\" \\\\ back\\ttab.mfw\"") != nil, true)

# ---- certificate text, checked directly ---------------------------------------------------------------------
rows = "9 9 9\n12 1 12\n1 10 10\n8 5 5\n3 8 3\n5 3 8\n10 12 1\n"
failures += same("rank line with leading zeros", outcome("007\n" + rows, 2, 2, 2)[:rank], 7)
failures += same("rows without a rank line need R", Metaflip:Gf2:TensorVerifier.read("R 9 9 9\nR 12 1 12\nR 1 10 10\nR 8 5 5\nR 3 8 3\nR 5 3 8\nR 10 12 1\n", 2, 2, 2).rank, 7)
failures += same("NUL and vertical tab are stripped from line ends", outcome("7\0\n\0 9 9 9\0\n12 1 12\n1 10 10\n8 5 5\n3 8 3\n5 3 8\n10 12 1\n\0\n", 2, 2, 2)[:rank], 7)
failures += same("a vertical tab is a word separator", outcome("7\n9" + 11.chr + "9 9\n12 1 12\n1 10 10\n8 5 5\n3 8 3\n5 3 8\n10 12 1\n", 2, 2, 2)[:rank], 7)
failures += same("tabs separate words", outcome("7\nR\t9\t9 9\n12 1 12\n1 10 10\n8 5 5\n3 8 3\n5 3 8\n10 12 1\n", 2, 2, 2)[:density], 36)
failures += same("no rank line and no R", outcome(rows, 2, 2, 2), "missing rank header or R prefix")
failures += same("hex digits in a decimal row", outcome("7\n" + rows.replace("9 9 9", "9 a 9"), 2, 2, 2), "malformed factor triple at term 0")
failures += same("R in the middle of a row", outcome("7\n" + rows.replace("9 9 9", "9 R 9"), 2, 2, 2), "malformed factor triple at term 0")
failures += same("a NUL inside a word", outcome("7\n9 9 9\n12 1\0 12\n1 10 10\n8 5 5\n3 8 3\n5 3 8\n10 12 1\n", 2, 2, 2), "malformed factor triple at term 1")
failures += same("huge rank", outcome("99999999999999999999999\n" + rows, 2, 2, 2), "wrong term count")
failures += same("huge factor", outcome("7\n" + rows.replace("9 9 9", "9 99999999999999999999999999999999999999999999999999999 9"), 2, 2, 2), "zero or out-of-bounds factor at term 0")
failures += same("16 does not fit 2x2", outcome("7\n" + rows.replace("9 9 9", "16 9 9"), 2, 2, 2), "zero or out-of-bounds factor at term 0")
failures += same("a zero factor", outcome("7\n" + rows.replace("9 9 9", "0 9 9"), 2, 2, 2), "zero or out-of-bounds factor at term 0")
failures += same("an all-zero-digit factor", outcome("7\n" + rows.replace("9 9 9", "000 9 9"), 2, 2, 2), "zero or out-of-bounds factor at term 0")
failures += same("a padded factor is fine", outcome("7\n" + rows.replace("9 9 9", "0009 9 9"), 2, 2, 2)[:rank], 7)
failures += same("the first bad row is the one reported", outcome("7\n" + rows.replace("12 1 12", "12 zz 12").replace("3 8 3", "0 8 3"), 2, 2, 2), "malformed factor triple at term 1")
failures += same("empty text", outcome("", 2, 2, 2), "empty tensor certificate")
failures += same("blank text", outcome("  \n\t\n", 2, 2, 2), "empty tensor certificate")
failures += same("just a rank", outcome("7", 2, 2, 2), "wrong term count")
failures += same("just a word", outcome("x", 2, 2, 2), "missing rank header or R prefix")
failures += same("R prefix in MFW1", outcome("MFW1 2 2 2 1\nR 1 1 1\n", 2, 2, 2), "R prefix in MFW1")
failures += same("MFW1 shape mismatch", outcome("MFW1 2 2 3 1\n1 1 1\n", 2, 2, 2), "MFW1 shape mismatch")
failures += same("MFW1 header with a zero", outcome("MFW1 2 0 2 1\n1 1 1\n", 2, 2, 2), "malformed MFW1 header")

# ---- one real process --------------------------------------------------------------------------------------------
tungsten = env("TUNGSTEN")
tungsten = file_expand_path(__DIR__ + "/../../../bin/tungsten") if tungsten == nil || tungsten == ""
tool = file_expand_path(__DIR__ + "/../tools/verify_tensor.w")
out_file = scratch + "/out.txt"
err_file = scratch + "/err.txt"
launch = -> (args) system("'" + tungsten + "' '" + tool + "' -- " + args + " > '" + out_file + "' 2> '" + err_file + "'")
good = launch.call("--shape 2x2x2 '" + strassen + "'")
failures += check("process: exit 0 for an exact certificate", good)
failures += same("process: stdout is the record", read_file(out_file), record_json("2x2x2", 7, 36, Digest.sha256(read_file(strassen)), expand(strassen)))
failures += same("process: nothing on stderr", read_file(err_file), "")
broken = launch.call("--shape 2x2x2 '" + fixtures + "/mutants/strassen_2x2x2__bit_flip_v.mfw'")
failures += check("process: exit 1 for an inexact certificate", !broken)
failures += same("process: no stdout on failure", read_file(out_file), "")
failures += same("process: stderr carries the message", read_file(err_file), failure_line("inexact GF(2) tensor at coefficients 3,3"))
launch.call("")
failures += same("process: usage error", read_file(err_file), failure_line("provide at least one certificate"))
system("rm -rf '" + scratch + "'")

if failures > 0
  << "verify_tensor: " + failures.to_s + " failure(s)"
  exit(1)
<< "PASS verify_tensor"
