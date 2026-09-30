# Bulk parity and timing for jsonx.w on many real JSON files (not part of the
# unit test: the FMM scheme tree is 1.8 GB).
#
#   tungsten -o json_bulk spec/gf2_support/json_bulk.w --release
#   ./json_bulk LISTFILE            # one path per line
#
# Prints `sha256-of-json.dumps(json.loads(file)) <TAB> path` for every file and
# the parse / dump / total times on stderr-style trailer lines starting with '#'.
# json_bulk.py prints the same table with Python's json module; the two outputs
# must be identical.
use core/crypto/sha256
use ../../lib/metaflip/gf2/jsonx

list = read_file(argv()[0])
parse_time = 0.0
dump_time = 0.0
bytes = 0
files = 0
list.split("\n").each -> (path)
  if path.size > 0
    raw = read_file(path)
    t0 = clock()
    tree = Jsonx.loads(raw)
    t1 = clock()
    text = Jsonx.dumps(tree)
    t2 = clock()
    << Crypto:SHA256.hexdigest(text) + "\t" + path
    parse_time = parse_time + (t1 - t0)
    dump_time = dump_time + (t2 - t1)
    bytes += raw.size
    files += 1
    Jsonx.release(tree)
    ccall("w_value_free_w", text)
    ccall("w_value_free_w", raw)
<< "# " + files.to_s + " files, " + bytes.to_s + " bytes, parse " + Floatx.fixed(parse_time, 3) + " s, dump " + Floatx.fixed(dump_time, 3) + " s"
