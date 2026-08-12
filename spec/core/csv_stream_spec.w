use core/csv
use core/io

-> check(name, actual, expected)
  if actual == expected
    << "PASS " + name
  else
    << "FAIL " + name + ": " + actual.to_s + " != " + expected.to_s
    exit 1

check("basic", CSV.parse("a,b\n1,2\n"), [["a", "b"], ["1", "2"]])
check("empty fields", CSV.parse(",x,\n"), [["", "x", ""]])
check("blank row", CSV.parse("\n"), [[""]])
check("custom separator", CSV.parse("a;b\n", ";"), [["a", "b"]])
check("quoted separator", CSV.parse("\"a,b\",c\n"), [["a,b", "c"]])
check("escaped quote", CSV.parse("\"a\"\"b\"\n"), [["a\"b"]])
check("quoted newline", CSV.parse("id,text\n1,\"hello\nworld\"\n"), [["id", "text"], ["1", "hello\nworld"]])
check("crlf", CSV.parse("a,b\r\n1,2\r\n"), [["a", "b"], ["1", "2"]])
check("SciIO integration", SciIO.parse_csv("\"a,b\",c\n"), [["a,b", "c"]])
check("SciIO line", SciIO.parse_csv_line("a,b", ","), ["a", "b"])

chunks = ["a,\"one", "\r\ntwo\"", ",z\r", "\nlast,row"]
chunk_rows = []
CSV.each_chunked(chunks) -> (row)
  chunk_rows.push(row)
check("chunk boundaries", chunk_rows, [["a", "one\r\ntwo", "z"], ["last", "row"]])

parser = CSVParser.new()
stream_rows = []
parser.feed("x,y\n1") -> (row)
  stream_rows.push(row)
check("feed yields complete only", stream_rows, [["x", "y"]])
parser.feed(",2") -> (row)
  stream_rows.push(row)
parser.finish() -> (row)
  stream_rows.push(row)
check("finish yields tail", stream_rows, [["x", "y"], ["1", "2"]])
check("finished predicate", parser.finished?, true)

unterminated = false
begin
  CSV.parse("\"open")
rescue error
  unterminated = error.to_s.include?("unterminated quoted field")
check("unterminated quote", unterminated, true)

bad_quote = false
begin
  CSV.parse("ab\"cd")
rescue error
  bad_quote = error.to_s.include?("quote inside an unquoted field")
check("quote placement", bad_quote, true)

bad_separator = false
begin
  CSV.parse("a,b", "::")
rescue error
  bad_separator = error.to_s.include?("CSV separator")
check("separator validation", bad_separator, true)

<< "csv_stream_spec: all checks passed"
