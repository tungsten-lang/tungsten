# Table — CSV parsing and rendering, the other exporters, describe/info and
# the aligned text grid (core/table.w).
#
# Run:
#   bin/tungsten run --interpret spec/core/table_csv_spec.w
#   bin/tungsten -o /tmp/table_csv_spec spec/core/table_csv_spec.w && /tmp/table_csv_spec

use core/table

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()
  << "PASS " + name

# String#lines keeps each terminator; these assertions want the bare line.
-> line_at(text, i)
  text.split("\n")[i]

# -------------------------------------------------------------- from_csv --

text = "name,age,score\nada,36,99.5\ngrace,45,88\n"
t = Table.from_csv(text)

check("csv columns", t.columns == [:name, :age, :score])
check("csv rows", t.size == 2)
check("csv strings stay strings", t[:name] == ["ada", "grace"])
check("csv ints are Int", type(t[:age][0]) == "Int")
check("csv int values", t[:age] == [36, 45])
check("csv decimals are Decimal", type(t[:score][0]) == "Decimal")
check("csv decimal values", t[:score] == [99.5, 88])
check("csv decimals are exact", t[:score][0] + 0.5 == 100)
check("csv name is a String", type(t[:name][0]) == "String")

check("negative numbers", Table.from_csv("a\n-12\n")[:a] == [-12])
check("plus signs", Table.from_csv("a\n+7\n")[:a] == [7])
check("not a number", Table.from_csv("a\n1.2.3\n")[:a] == ["1.2.3"])
check("bare dot is not a number", Table.from_csv("a\n.\n")[:a] == ["."])
check("empty field is nil", Table.from_csv("a,b\n,2\n")[:a] == [nil])
check("whitespace trims for numbers", Table.from_csv("a\n 12 \n")[:a] == [12])
check("infer off keeps strings", type(Table.from_csv("a\n1\n", infer: false)[:a][0]) == "String")

no_header = Table.from_csv("1,2\n3,4\n", headers: false)
check("no header names", no_header.columns == [Table.normalize_name("c0"), Table.normalize_name("c1")])
check("no header rows", no_header.size == 2)
check("no header values", no_header["c0"] == [1, 3])

check("custom separator", Table.from_csv("a;b\n1;2\n", separator: ";").columns == [:a, :b])
check("custom separator values", Table.from_csv("a;b\n1;2\n", separator: ";")[:b] == [2])

check("empty document", Table.from_csv("").size == 0)
check("header only", Table.from_csv("a,b\n").size == 0)
check("header only columns", Table.from_csv("a,b\n").columns == [:a, :b])

# RFC 4180 quoting survives the parser.
quoted = Table.from_csv("a,b\n\"x,y\",\"he said \"\"hi\"\"\"\n")
check("quoted separator", quoted[:a] == ["x,y"])
check("escaped quote", quoted[:b] == ["he said \"hi\""])
embedded = Table.from_csv("a\n\"one\ntwo\"\n")
check("quoted newline", embedded[:a] == ["one\ntwo"])

# ---------------------------------------------------------------- to_csv --

check("to_csv round-trips", t.to_csv == text)
check("to_csv header", line_at(t.to_csv, 0) == "name,age,score")
check("to_csv separator", t.to_csv(";") == "name;age;score\nada;36;99.5\ngrace;45;88\n")
check("to_csv nil is empty", Table.new({:a => [nil]}).to_csv == "a\n\n")
check("to_csv quotes separators", Table.new({:a => ["x,y"]}).to_csv == "a\n\"x,y\"\n")
check("to_csv doubles quotes", Table.new({:a => ["he \"said\""]}).to_csv == "a\n\"he \"\"said\"\"\"\n")
check("to_csv quotes newlines", Table.new({:a => ["one\ntwo"]}).to_csv == "a\n\"one\ntwo\"\n")
check("to_csv quotes only when needed", Table.new({:a => ["plain"]}).to_csv == "a\nplain\n")

# A full parse -> render -> parse cycle preserves values and types.
tricky = Table.new({:label => ["x,y", "he \"said\"", "one\ntwo"], :n => [1, 2, 3]})
cycled = Table.from_csv(tricky.to_csv)
check("quoting round-trips values", cycled[:label] == tricky[:label])
check("quoting round-trips numbers", cycled[:n] == [1, 2, 3])
check("quoting round-trips whole table", cycled == tricky)

semi = Table.from_csv(tricky.to_csv(";"), separator: ";")
check("semicolon round-trips", semi == tricky)

# ------------------------------------------------------------ file round --

path = "/tmp/tungsten_table_csv_spec.csv"
File.write(path, text)
loaded = Table.load(path)
check("load reads a file", loaded == t)
check("load with separator", Table.load(path, ",") == t)
File.delete(path)
check("spec file cleaned up", !File.exists?(path))

# --------------------------------------------------------------- exports --

check("to_json", t.to_json == "\[{\"name\":\"ada\",\"age\":36,\"score\":99.5},{\"name\":\"grace\",\"age\":45,\"score\":88}\]")
check("to_json null", Table.new({:a => [nil]}).to_json == "\[{\"a\":null}\]")
check("to_json escapes", Table.new({:a => ["he \"said\""]}).to_json == "\[{\"a\":\"he \\\"said\\\"\"}\]")
check("to_json empty", Table.new.to_json == "\[\]")

html = t.to_html
check("to_html opens", line_at(html, 0) == "<table>")
check("to_html headers", html.contains?("<th>name</th><th>age</th><th>score</th>"))
check("to_html cells", html.contains?("<td>ada</td><td>36</td><td>99.5</td>"))
check("to_html escapes", Table.new({:a => ["a<b&c"]}).to_html.contains?("<td>a&lt;b&amp;c</td>"))

xml = t.to_xml
check("to_xml rows", xml.contains?("<row>"))
check("to_xml fields", xml.contains?("<name>ada</name>"))
check("to_xml custom tag", t.to_xml("person").contains?("<person>"))
check("to_xml escapes", Table.new({:a => ["<x>"]}).to_xml.contains?("<a>&lt;x&gt;</a>"))

sql = t.to_sql("people")
check("to_sql statements", sql.lines.size == 2)
check("to_sql first row", line_at(sql, 0) == "INSERT INTO people (name, age, score) VALUES ('ada', 36, 99.5);")
check("to_sql null", Table.new({:a => [nil]}).to_sql("x") == "INSERT INTO x (a) VALUES (NULL);\n")
check("to_sql escapes quotes", Table.new({:a => ["o'hara"]}).to_sql("x").contains?("'o''hara'"))

# -------------------------------------------------------------- describe --

d = t.describe
check("describe columns", d.columns == [:statistic, :age, :score])
check("describe rows", d.size == 4)
check("describe statistics", d[:statistic] == ["count", "mean", "min", "max"])
check("describe count", d[:age][0] == 2)
check("describe mean", d[:age][1] == 40.5)
check("describe min", d[:age][2] == 36)
check("describe max", d[:age][3] == 45)
check("describe is exact", d[:score][1] == 93.75)
check("describe skips text columns", !d.covers?(:name))
check("describe of a text-only table", Table.new({:a => ["x"]}).describe.columns == [:statistic])

gaps = Table.new({:a => [1, nil, 5]})
check("describe skips nil in count", gaps.describe[:a][0] == 2)
check("describe skips nil in mean", gaps.describe[:a][1] == 3)

# ------------------------------------------------------------ histogram --

h = Table.new({:a => [1, 2, 3, 4]}).histogram(:a, 2)
check("histogram columns", h.columns == [:lower, :upper, :count])
check("histogram bins", h.size == 2)
check("histogram counts", h[:count] == [2, 2])
check("histogram bounds", h[:lower] == [1, 2.5])
flat = Table.new({:a => [7, 7]}).histogram(:a, 2)
check("histogram of a flat column", flat[:count] == [2, 0])
freq = Table.new({:a => ["x", "y", "x"]}).histogram(:a)
check("categorical histogram columns", freq.columns == [:value, :count])
check("categorical histogram values", freq[:value] == ["x", "y"])
check("categorical histogram counts", freq[:count] == [2, 1])

# ------------------------------------------------------------------ info --

info = t.info
check("info headline", line_at(info, 0) == "Table: 2 rows, 3 columns")
check("info lists columns", info.contains?("name") && info.contains?("age") && info.contains?("score"))
check("info reports types", info.contains?("String") && info.contains?("Int") && info.contains?("Decimal"))
check("info counts non-nil", Table.new({:a => [1, nil]}).info.contains?("1 non-nil"))

# ---------------------------------------------------------------- to_s --

grid = Table.new({:name => ["ada", "grace"], :age => [36, 145]}).to_s
expected = "# | name  | age\n--+-------+----\n0 | ada   |  36\n1 | grace | 145"
check("grid layout", grid == expected)
check("grid has no trailing spaces", !grid.contains?(" \n"))
check("grid text is left aligned", line_at(grid, 2) == "0 | ada   |  36")
check("grid numbers are right aligned", line_at(grid, 3) == "1 | grace | 145")

wide = Table.new({:n => [1], :description => ["a longer value"]}).to_s
check("wide column header", line_at(wide, 0) == "# | n | description")
check("wide column rule", line_at(wide, 1) == "--+---+---------------")

check("empty grid", Table.new.to_s == "(0 rows, 0 columns)")
check("no rows grid", Table.from_csv("a,b\n").to_s == "# | a | b\n--+---+--")
check("nil renders as blank", Table.new({:a => [nil, 1]}).to_s == "# | a\n--+--\n0 |\n1 | 1")

labelled = Table.new({:a => [1, 2]}, index: ["north", "south"]).to_s
check("index labels in the grid", line_at(labelled, 2) == "north | 1")
check("index header widens", line_at(labelled, 0) == "#     | a")

check("inspect adds a summary", t.inspect == t.to_s + "\n(2 rows, 3 columns)")
check("inspect of an empty table", Table.new.inspect == "(0 rows, 0 columns)\n(0 rows, 0 columns)")

# ---------------------------------------------------------------- errors --

bad_separator = false
begin
  Table.from_csv("a,b\n", separator: "::")
rescue error
  bad_separator = error.to_s.include?("CSV separator")
check("bad separator raises", bad_separator)

unterminated = false
begin
  Table.from_csv("a\n\"open\n")
rescue error
  unterminated = error.to_s.include?("unterminated quoted field")
check("unterminated quote raises", unterminated)

missing_file = false
begin
  Table.load("/tmp/tungsten_table_csv_spec_missing.csv")
rescue error
  missing_file = true
check("missing file raises", missing_file)

<< "ALL PASS table_csv_spec ([passed.load()] checks)"
