# Parity driver (not a self-test): the strict MFW1 reader, alone, on many files.
#
#   gf2_scheme_parse_parity LISTFILE      one certificate path per line
#
# prints one line per path, `ACCEPT<TAB>path<TAB>rank<TAB>sha256-of-blob` when
# Metaflip:Gf2:Scheme.parse takes the file (without judging the tensor) and
# `REJECT<TAB>path<TAB>message` otherwise. spec/verify_tensor_parity_test.py
# (`parse-fuzz`) compares these verdicts with read_blob of the Python tooling on
# thousands of damaged canonical files; the only differences allowed are the
# documented ones (negative numbers and non-positive dimensions, which read_blob
# lets through and every later exactness check refuses).
use ../lib/metaflip/gf2/scheme

args = argv()
if args.size != 1
  << "usage: gf2_scheme_parse_parity LISTFILE"
  exit(2)
listing = read_file(args[0])
if listing == nil
  << "cannot read " + args[0]
  exit(2)
listing.split("\n").each -> (path)
  if path != ""
    text = read_file(path)
    begin
      scheme = Metaflip:Gf2:Scheme.parse(text)
      << "ACCEPT\t" + path + "\t" + scheme.rank.to_s + "\t" + scheme.sha256
      scheme.release
    rescue failure
      << "REJECT\t" + path + "\t[failure]"
