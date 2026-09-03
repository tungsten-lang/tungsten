# Table — construction, shape, access, projection, filtering and ordering
# (core/table.w).
#
# Run:
#   bin/tungsten run --interpret spec/core/table_spec.w
#   bin/tungsten -o /tmp/table_spec spec/core/table_spec.w && /tmp/table_spec

use core/table

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()
  << "PASS " + name

# ---------------------------------------------------------- construction --

t = Table.new({:name => ["ada", "grace", "alan", "edsger"], :age => [36, 45, 41, 45], :city => ["lon", "nyc", "lon", "ams"]})

check("constructs", type(t) == "Table")
check("is_a? Table", t.is_a?(Table))
check("row count", t.size == 4)
check("length alias", t.length == 4)
check("row_count alias", t.row_count == 4)
check("column count", t.column_count == 3)
check("width alias", t.width == 3)
check("shape", t.shape == [4, 3])
check("dimensions", t.dimensions == [4, 3])
check("columns", t.columns == [:name, :age, :city])
check("column_names alias", t.column_names == [:name, :age, :city])
check("keys alias", t.keys == [:name, :age, :city])
check("not blank", !t.blank?)
check("not empty", !t.empty?)
check("default index", t.index == [0, 1, 2, 3])
check("axes", t.axes == [[0, 1, 2, 3], [:name, :age, :city]])

# String column names normalize to the same Symbol key.
s = Table.new({"name" => ["ada"], "age" => [36]})
check("string names normalize", s.columns == [:name, :age])
check("string lookup", s["name"] == ["ada"])
check("symbol lookup", s[:name] == ["ada"])

# From an Array of row Hashes; column order is first-seen order and a row that
# omits a key gets nil.
r = Table.new([{:a => 1, :b => 2}, {:b => 20, :c => 30}])
check("rows: columns", r.columns == [:a, :b, :c])
check("rows: size", r.size == 2)
check("rows: fill nil", r[:a] == [1, nil])
check("rows: later key", r[:c] == [nil, 30])
check("from_rows", Table.from_rows([{:a => 1}]).size == 1)
check("from_records", Table.from_records([{:a => 1}])[:a] == [1])
check("from_columns", Table.from_columns({:a => [1, 2]}).size == 2)

# Positional rows plus explicit column names.
p = Table.from_rows([[1, "x"], [2, "y"]], [:n, :s])
check("positional columns", p.columns == [:n, :s])
check("positional values", p[:n] == [1, 2])

check("empty table", Table.new.size == 0)
check("empty is blank", Table.empty.blank?)
check("empty columns", Table.new.columns == [])

# The table owns its storage: mutating the source Array must not reach in.
source = [1, 2]
owned = Table.new({:a => source})
source.push(3)
check("constructor copies columns", owned[:a] == [1, 2])
grabbed = owned[:a]
grabbed.push(99)
check("accessor copies columns", owned[:a] == [1, 2])

# Row index.
idx = Table.new({:a => [1, 2]}, index: [:x, :y])
check("index labels", idx.index == [:x, :y])
check("index survives head", idx.head(1).index == [:x])

# ---------------------------------------------------------------- access --

check("column by symbol", t[:age] == [36, 45, 41, 45])
check("column by string", t["age"] == [36, 45, 41, 45])
check("column method", t.column(:age) == [36, 45, 41, 45])
check("row by int", t[1] == {:name => "grace", :age => 45, :city => "nyc"})
check("row method", t.row(0) == {:name => "ada", :age => 36, :city => "lon"})
check("negative row", t.row(-1)[:name] == "edsger")
check("at row", t.at(2) == t.row(2))
check("at cell", t.at(1, :name) == "grace")
check("at cell by string", t.at(1, "name") == "grace")
check("xs", t.xs(0) == t.row(0))
check("first", t.first[:name] == "ada")
check("last", t.last[:name] == "edsger")
check("covers?", t.covers?(:age) && t.covers?("age"))
check("covers? missing", !t.covers?(:height))
check("has_column? alias", t.has_column?(:city))
check("values", t.values[0] == ["ada", 36, "lon"])
check("to_a", t.to_a.size == 4 && t.to_a[0][:name] == "ada")
check("to_records", t.to_records == t.to_a)
check("to_h", t.to_h[:age] == [36, 45, 41, 45])

check("head default", t.head.size == 4)
check("head n", t.head(2)[:name] == ["ada", "grace"])
check("head over-long", t.head(99).size == 4)
check("tail n", t.tail(2)[:name] == ["alan", "edsger"])
check("take", t.take(1)[:name] == ["ada"])
check("drop rows", t.drop(3)[:name] == ["edsger"])
check("between", t.between(1, 2)[:name] == ["grace", "alan"])
check("truncate", t.truncate(0, 1)[:name] == ["ada", "grace"])
check("slice", t.slice(1, 2)[:name] == ["grace", "alan"])
check("slice clamps", t.slice(3, 99).size == 1)

# --------------------------------------------------------------- columns --

check("select list", t.select([:name, :age]).columns == [:name, :age])
check("select reorders", t.select([:age, :name]).columns == [:age, :name])
check("select string name", t.select("age").columns == [:age])
check("select keeps rows", t.select([:age]).size == 4)
check("except", t.except(:city).columns == [:name, :age])
check("except list", t.except([:name, :city]).columns == [:age])
check("drop_columns alias", t.drop_columns(:city).columns == [:name, :age])
check("drop by name", t.drop(:city).columns == [:name, :age])
check("rename", t.rename({:age => :years}).columns == [:name, :years, :city])
check("rename keeps values", t.rename({:age => :years})[:years] == [36, 45, 41, 45])

check("map_column", t.map_column(:age, -> (v) v + 1)[:age] == [37, 46, 42, 46])
check("map_column leaves others", t.map_column(:age, -> (v) v + 1)[:name] == t[:name])
check("with_column array", t.with_column(:z, [1, 2, 3, 4])[:z] == [1, 2, 3, 4])
check("with_column scalar", t.with_column(:z, 7)[:z] == [7, 7, 7, 7])
check("with_column replaces", t.with_column(:age, [0, 0, 0, 0])[:age] == [0, 0, 0, 0])
check("with_column appends", t.with_column(:z, 1).columns == [:name, :age, :city, :z])
check("compute_column", t.compute_column(:tag, -> (row) row[:name] + "!")[:tag] == ["ada!", "grace!", "alan!", "edsger!"])
check("apply", t.select([:age]).apply(-> (name, values) values.map(-> (v) v * 2))[:age] == [72, 90, 82, 90])
check("mask", t.select([:age]).mask(-> (name, v) v > 40)[:age] == [36, nil, nil, nil])
check("replace", t.replace(36, 99)[:age] == [99, 45, 41, 45])
check("copy equals", t.copy == t)
check("copy is separate", t.copy.with_column(:z, 1).columns != t.columns)

# --------------------------------------------------------------- filters --

check("where", t.where(-> (row) row[:age] > 40).size == 3)
check("where keeps order", t.where(-> (row) row[:city] == "lon")[:name] == ["ada", "alan"])
check("filter alias", t.filter(-> (row) row[:age] == 45).size == 2)
check("query alias", t.query(-> (row) row[:age] == 45).size == 2)
check("exclude", t.exclude(-> (row) row[:age] == 45)[:name] == ["ada", "alan"])
check("where none", t.where(-> (row) false).size == 0)
check("where all", t.where(-> (row) true) == t)
check("find_row", t.find_row(-> (row) row[:age] == 41)[:name] == "alan")
check("find_row miss", t.find_row(-> (row) false) == nil)
check("map_rows", t.map_rows(-> (row) row[:age]) == [36, 45, 41, 45])
check("reduce_rows", t.reduce_rows(0, -> (acc, row) acc + row[:age]) == 167)

seen = []
t.each_row -> (row)
  seen.push(row[:name])
check("each_row", seen == ["ada", "grace", "alan", "edsger"])

seen2 = []
t.each -> (row)
  seen2.push(row[:city])
check("each", seen2 == ["lon", "nyc", "lon", "ams"])

# ----------------------------------------------------------------- order --

check("sort_by asc", t.sort_by(:age)[:name] == ["ada", "alan", "grace", "edsger"])
check("sort_by desc", t.sort_by(:age, true)[:name] == ["grace", "edsger", "alan", "ada"])
check("sort_by is stable", t.sort_by(:age)[:name] == ["ada", "alan", "grace", "edsger"])
check("sort_by desc is stable", t.sort_by(:age, true)[:name] == ["grace", "edsger", "alan", "ada"])
check("sort_by multi key", t.sort_by([:city, :age])[:name] == ["edsger", "ada", "alan", "grace"])
check("sort_by string name", t.sort_by("age")[:age] == [36, 41, 45, 45])
check("sort lexicographic", t.sort[:name] == ["ada", "alan", "edsger", "grace"])
check("reverse", t.reverse[:name] == ["edsger", "alan", "grace", "ada"])
check("sort_by keeps columns", t.sort_by(:age).columns == t.columns)

dup = Table.new({:a => [1, 1, 2], :b => ["x", "x", "y"]})
check("uniq", dup.uniq.size == 2)
check("uniq keeps first", dup.uniq[:a] == [1, 2])
mixed = Table.new({:a => [1, "1"]})
check("uniq is type aware", mixed.uniq.size == 2)

gaps = Table.new({:a => [3, nil, 1]})
check("sort_by nil first", gaps.sort_by(:a)[:a] == [nil, 1, 3])
check("sort_by nil last desc", gaps.sort_by(:a, true)[:a] == [3, 1, nil])

# ------------------------------------------------------------- mutation --

# `<<` is the one mutator; the infix form does not reach a user-defined `<<`
# on either engine, so `push` (or the explicit `.<<()` call) is the spelling.
box = Table.new
box.push({:a => 1, :b => 2})
check("push builds columns", box.columns == [:a, :b])
box.push({:a => 3, :b => 4})
check("push adds rows", box.size == 2)
box.push([5, 6])
check("push array row", box[:a] == [1, 3, 5])
check("push returns self", box.push({:a => 7, :b => 8}).size == 4)
box2 = Table.new
box2.<<({:a => 1})
check("explicit << call", box2.size == 1)

derived = box.head(2)
box.push({:a => 9, :b => 9})
check("derived table unaffected", derived.size == 2)

# ------------------------------------------------------------ arithmetic --

n = Table.new({:a => [1, 2, 3], :b => [10, 20, 30]})
check("plus scalar", (n + 1)[:a] == [2, 3, 4])
check("minus scalar", (n - 1)[:b] == [9, 19, 29])
check("times scalar", (n * 2)[:a] == [2, 4, 6])
check("divide scalar", (n / 2)[:b] == [5, 10, 15])
check("mod scalar", (n % 3)[:b] == [1, 2, 0])
check("add table", n.add(n)[:a] == [2, 4, 6])
check("subtract table", n.subtract(n)[:b] == [0, 0, 0])
check("multiply table", n.multiply(n)[:a] == [1, 4, 9])
check("divide table", n.divide(n)[:a] == [1, 1, 1])
check("mod table", n.mod(n)[:a] == [0, 0, 0])
check("arithmetic skips non numeric", (t + 1)[:name] == t[:name])
check("sample is bounded", n.sample(99).size == 3)
check("seeded sample is reproducible", n.sample(2, 42) == n.sample(2, 42))
check("seeded sample size", n.sample(2, 42).size == 2)
check("seeded sample keeps columns", n.sample(1, 7).columns == [:a, :b])
check("decimals stay exact", (Table.new({:a => [1.5, 2.25]}) + 1)[:a] == [2.5, 3.25])

m = Table.new({:x => [1, 0], :y => [0, 1]})
check("dot identity", n.dot(m)[:x] == [1, 2, 3])
check("dot columns", n.dot(m).columns == [:x, :y])

# -------------------------------------------------------------- reshape --

check("transpose columns", n.transpose.columns == [:column, Table.normalize_name("0"), Table.normalize_name("1"), Table.normalize_name("2")])
check("transpose values", n.transpose[:column] == [:a, :b])
check("squeeze cell", n.select([:a]).head(1).squeeze == 1)
check("squeeze column", n.select([:a]).squeeze == [1, 2, 3])
check("squeeze row", n.head(1).squeeze == {:a => 1, :b => 10})
check("squeeze keeps table", n.squeeze == n)
check("shift", n.shift(1)[:a] == [nil, 1, 2])
check("shift back", n.shift(-1)[:a] == [2, 3, nil])
check("diff", n.diff[:b] == [nil, 10, 10])
check("diff n", n.diff(2)[:a] == [nil, nil, 2])
check("cumulative sum", n.cumulative(:sum)[:a] == [1, 3, 6])
check("cumulative max", n.cumulative(:max)[:a] == [1, 2, 3])
check("append hash", n.append({:a => 4, :b => 40}).size == 4)
check("append table", n.append(n)[:a] == [1, 2, 3, 1, 2, 3])
check("append widens", n.append({:c => 1}).columns == [:a, :b, :c])
check("interpolate", Table.new({:a => [1, nil, 3, nil]}).interpolate[:a] == [1, 2, 3, 3])
check("interpolate leading", Table.new({:a => [nil, 2, 4]}).interpolate[:a] == [2, 2, 4])
check("resample mean", n.resample(2)[:a] == [1.5, 3])
check("resample sum", n.resample(2, :sum)[:b] == [30, 30])
check("reindex", n.reindex([2, 0])[:a] == [3, 1])
check("reindex unknown", n.reindex([99])[:a] == [nil])
check("with_index", n.with_index([:p, :q, :r]).index == [:p, :q, :r])
check("align widens both", n.align(m)[0].columns == [:a, :b, :x, :y])
check("align fills nil", n.align(m)[0][:x] == [nil, nil, nil])

pv = Table.new({:day => ["mon", "mon", "tue"], :kind => ["x", "y", "x"], :n => [1, 2, 3]})
check("pivot columns", pv.pivot(:day, :kind, :n).columns == [:day, Table.normalize_name("x"), Table.normalize_name("y")])
check("pivot values", pv.pivot(:day, :kind, :n)["x"] == [1, 3])
check("pivot gaps", pv.pivot(:day, :kind, :n)["y"] == [2, nil])

# -------------------------------------------------------------- equality --

check("equal tables", Table.new({:a => [1]}) == Table.new({:a => [1]}))
check("different values", Table.new({:a => [1]}) != Table.new({:a => [2]}))
check("different columns", Table.new({:a => [1]}) != Table.new({:b => [1]}))
check("different rows", Table.new({:a => [1]}) != Table.new({:a => [1, 2]}))
check("not a table", Table.new({:a => [1]}) != 3)
check("eql? alias", Table.new({:a => [1]}).eql?(Table.new({:a => [1]})))

# ---------------------------------------------------------------- errors --

missing = false
begin
  t[:height]
rescue error
  missing = error.to_s.include?("has no column 'height'")
check("missing column raises", missing)

mismatch = false
begin
  Table.new({:a => [1, 2], :b => [3]})
rescue error
  mismatch = error.to_s.include?("has 1 rows, expected 2")
check("length mismatch raises", mismatch)

out_of_range = false
begin
  t.row(99)
rescue error
  out_of_range = error.to_s.include?("out of range")
check("row out of range raises", out_of_range)

bad_name = false
begin
  Table.new({1 => [1]})
rescue error
  bad_name = error.to_s.include?("must be a Symbol or a String")
check("bad column name raises", bad_name)

bad_index = false
begin
  n.with_index([:only])
rescue error
  bad_index = error.to_s.include?("index has 1 labels")
check("bad index length raises", bad_index)

duplicated = false
begin
  t.select([:age, :age])
rescue error
  duplicated = error.to_s.include?("listed twice")
check("duplicate selection raises", duplicated)

not_numeric = false
begin
  t.mean(:name)
rescue error
  not_numeric = error.to_s.include?("is not numeric")
check("non numeric aggregate raises", not_numeric)

bad_shape = false
begin
  n + Table.new({:zz => [1]})
rescue error
  bad_shape = error.to_s.include?("matching columns")
check("arithmetic shape raises", bad_shape)

bad_width = false
begin
  n.push([1])
rescue error
  bad_width = error.to_s.include?("expected 2")
check("short row raises", bad_width)

bad_operand = false
begin
  n + "text"
rescue error
  bad_operand = error.to_s.include?("needs a number or a Table")
check("non numeric operand raises", bad_operand)

bad_apply = false
begin
  n.apply(-> (name, values) 1)
rescue error
  bad_apply = error.to_s.include?("must return an Array")
check("apply must return an array", bad_apply)

bad_resample = false
begin
  n.resample(0)
rescue error
  bad_resample = error.to_s.include?("positive bucket size")
check("resample needs a positive bucket", bad_resample)

<< "ALL PASS table_spec ([passed.load()] checks)"
