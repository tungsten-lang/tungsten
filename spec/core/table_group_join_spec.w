# Table — grouping, aggregation and joins (core/table.w).
#
# Run:
#   bin/tungsten run --interpret spec/core/table_group_join_spec.w
#   bin/tungsten -o /tmp/table_group_join_spec spec/core/table_group_join_spec.w && /tmp/table_group_join_spec

use core/table

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()
  << "PASS " + name

staff = Table.new({
  :name => ["ada", "grace", "alan", "edsger", "barbara"],
  :city => ["lon", "nyc", "lon", "ams", "nyc"],
  :team => ["core", "core", "tools", "core", "tools"],
  :pay => [100, 200, 300, 400, 500]
})

# ---------------------------------------------------- column aggregations --

check("count", staff.count == 5)
check("counts all", staff.counts == {:name => 5, :city => 5, :team => 5, :pay => 5})
check("counts one", staff.counts(:pay) == 5)
check("sum", staff.sum(:pay) == 1500)
check("sum is exact int", type(staff.sum(:pay)) == "Int")
check("mean", staff.mean(:pay) == 300)
check("min", staff.min(:pay) == 100)
check("max", staff.max(:pay) == 500)
check("median", staff.median(:pay) == 300)
check("product", staff.product(:pay) == 100 * 200 * 300 * 400 * 500)
check("variance", staff.variance(:pay) == 25000)
check("std", staff.std(:pay) > 158 && staff.std(:pay) < 159)
check("mode", staff.mode(:team) == "core")
check("mode breaks ties by first appearance", staff.mode(:city) == "lon")
check("mode of every column", staff.mode(:name) == "ada")
check("quantile median", staff.quantile(:pay, 0.5) == 300)
check("quantile low", staff.quantile(:pay, 0) == 100)
check("quantile high", staff.quantile(:pay, 1) == 500)
check("quantile interpolates", staff.quantile(:pay, 0.25) == 200)
check("rank", staff.rank(:pay) == [1, 2, 3, 4, 5])
check("rank ties share", Table.new({:a => [5, 1, 5]}).rank(:a) == [2, 1, 2])
check("numeric_columns", staff.numeric_columns == [:pay])

check("zero-arg sum hash", staff.sum == {:pay => 1500})
check("zero-arg mean hash", staff.mean == {:pay => 300})
check("zero-arg min hash", staff.min == {:pay => 100})
check("zero-arg max hash", staff.max == {:pay => 500})
check("zero-arg median hash", staff.median == {:pay => 300})
check("aggregate", staff.aggregate(:sum) == {:pay => 1500})
check("aggregate count", staff.aggregate(:count) == {:pay => 5})

# Exactness: an Int column means an exact mean, and Decimals stay Decimals.
exact = Table.new({:a => [1, 2, 3], :d => [1.5, 2.5, 3.5]})
check("mean of ints is exact", exact.mean(:a) == 2)
check("mean of decimals is exact", exact.mean(:d) == 2.5)
check("mean avoids int division", Table.new({:a => [1, 2]}).mean(:a) == 1.5)
check("sum of decimals is exact", exact.sum(:d) == 7.5)

# nil cells are skipped, not counted.
holes = Table.new({:a => [1, nil, 3]})
check("counts skip nil", holes.counts(:a) == 2)
check("sum skips nil", holes.sum(:a) == 4)
check("mean skips nil", holes.mean(:a) == 2)
check("numeric column with nil", holes.numeric_columns == [:a])

check("all", Table.new({:a => [1, 2]}).all)
check("all false with nil", !Table.new({:a => [1, nil]}).all)
check("any", Table.new({:a => [nil, 1]}).any)
check("any false", !Table.new({:a => [nil, nil]}).any)

check("covariance sign", exact.covariance(:a, :d) > 0)
check("correlation identical", exact.correlation(:a, :a) == 1)
check("covariance matrix shape", exact.covariance.shape == [2, 3])
check("covariance matrix labels", exact.covariance[:column] == [:a, :d])
check("correlation matrix diagonal", exact.correlation[:a][0] == 1 && exact.correlation[:d][1] == 1)

spread = Table.new({:a => [1, 2, 3, 10]})
check("skew positive", spread.skew(:a) > 0)
check("skew needs 3 rows", Table.new({:a => [1, 2]}).skew(:a) == nil)
check("kurtosis needs 4 rows", Table.new({:a => [1, 2, 3]}).kurtosis(:a) == nil)
check("kurtosis computes", spread.kurtosis(:a) != nil)
check("kurtosis of a flat column is nil", Table.new({:a => [2, 2, 2, 2]}).kurtosis(:a) == nil)

# ------------------------------------------------------------- group_by --

by_city = staff.group_by(:city)
check("group count", by_city.size == 3)
check("group length alias", by_city.length == 3)
check("group keys", by_city.keys == [:city])
check("group labels in first-seen order", by_city.labels == ["lon", "nyc", "ams"])
check("group lookup", by_city["lon"].size == 2)
check("group lookup miss", by_city["zzz"] == nil)
check("group has_key?", by_city.has_key?("nyc"))
check("group member is a table", type(by_city["lon"]) == "Table")
check("group member rows", by_city["lon"][:name] == ["ada", "alan"])
check("group to_h", by_city.to_h["ams"][:name] == ["edsger"])
check("group tables", by_city.tables.size == 3)
check("group to_s", by_city.to_s == "TableGroups(city: 3 groups)")

seen = []
by_city.each -> (label, group)
  seen.push(label + ":" + group.size.to_s)
check("group each", seen == ["lon:2", "nyc:2", "ams:1"])

counted = by_city.count
check("group count table columns", counted.columns == [:city, :count])
check("group count values", counted[:count] == [2, 2, 1])
check("group count labels", counted[:city] == ["lon", "nyc", "ams"])

check("group sum", by_city.sum(:pay)[:pay] == [400, 700, 400])
check("group sum columns", by_city.sum(:pay).columns == [:city, :pay])
check("group mean", by_city.mean(:pay)[:pay] == [200, 350, 400])
check("group min", by_city.min(:pay)[:pay] == [100, 200, 400])
check("group max", by_city.max(:pay)[:pay] == [300, 500, 400])
check("group median", by_city.median(:pay)[:pay] == [200, 350, 400])
check("group product", by_city.product(:pay)[:pay] == [30000, 100000, 400])
check("group variance", by_city.variance(:pay)[:pay] == [20000, 45000, nil])
# Spelled with a String: the compiled front end rewrites a Symbol *literal*
# handed to a method named `count` into a block before user dispatch.
check("group count of column", by_city.count("pay")[:pay] == [2, 2, 1])

agg = by_city.agg({:pay => :mean})
check("group agg columns", agg.columns == [:city, :pay])
check("group agg values", agg[:pay] == [200, 350, 400])

# Multi-key grouping: labels become Arrays and the result carries both keys.
pairs = Table.new({
  :city => ["lon", "lon", "nyc", "lon", "nyc"],
  :team => ["core", "tools", "core", "core", "core"],
  :pay => [10, 20, 30, 40, 50]
})
by_pair = pairs.group_by([:city, :team])
check("multi-key groups", by_pair.size == 3)
check("multi-key labels", by_pair.labels[0] == ["lon", "core"])
multi = by_pair.sum(:pay)
check("multi-key columns", multi.columns == [:city, :team, :pay])
check("multi-key city column", multi[:city] == ["lon", "lon", "nyc"])
check("multi-key team column", multi[:team] == ["core", "tools", "core"])
check("multi-key sums", multi[:pay] == [50, 20, 80])
check("multi-key counts", by_pair.count[:count] == [2, 1, 2])

# Grouping is type-aware, so 1 and "1" never land in the same bucket.
typed = Table.new({:k => [1, "1", 1], :v => [10, 20, 30]})
check("group is type aware", typed.group_by(:k).size == 2)
check("group type aware sums", typed.group_by(:k).sum(:v)[:v] == [40, 20])

# Grouping a single-row table, and a grouped column that is also aggregated.
one = Table.new({:k => ["a"], :v => [1]})
check("single group", one.group_by(:k).sum(:v)[:v] == [1])
numeric_key = Table.new({:k => [1, 1, 2], :v => [10, 20, 30]})
check("aggregating the key renames", numeric_key.group_by(:k).sum(:k).columns == [:k, :k_agg])
check("aggregating the key values", numeric_key.group_by(:k).sum(:k)[:k_agg] == [2, 2])

# Group members are ordinary tables and keep the parent's row order.
check("group member sorts", by_city["nyc"].sort_by(:pay)[:name] == ["grace", "barbara"])

# ---------------------------------------------------------------- joins --

cities = Table.new({:city => ["lon", "nyc", "ber"], :country => ["uk", "us", "de"]})

inner = staff.join(cities, :city)
check("inner size", inner.size == 4)
check("inner columns", inner.columns == [:name, :city, :team, :pay, :country])
check("inner drops unmatched", !Table.member?(inner[:name], "edsger"))
check("inner values", inner[:country] == ["uk", "us", "uk", "us"])
check("inner_join alias", staff.inner_join(cities, :city) == inner)
check("default kind is inner", staff.join(cities, :city, :inner) == inner)

left = staff.join(cities, :city, :left)
check("left size", left.size == 5)
check("left keeps unmatched", left[:name] == ["ada", "grace", "alan", "edsger", "barbara"])
check("left fills nil", left[:country] == ["uk", "us", "uk", nil, "us"])
check("left_join alias", staff.left_join(cities, :city) == left)

# One-to-many fans out; a left row with no match still appears once.
many = Table.new({:city => ["lon", "lon"], :zone => [1, 2]})
fanned = Table.new({:city => ["lon", "ams"], :n => [1, 2]}).join(many, :city, :left)
check("fan-out rows", fanned.size == 3)
check("fan-out zones", fanned[:zone] == [1, 2, nil])
check("fan-out left values", fanned[:n] == [1, 1, 2])

# Colliding non-key column names get a _right suffix.
collide = Table.new({:city => ["lon"], :pay => [999]})
joined = staff.join(collide, :city)
check("collision renames", joined.columns == [:name, :city, :team, :pay, :pay_right])
check("collision keeps left", joined[:pay] == [100, 300])
check("collision carries right", joined[:pay_right] == [999, 999])

# Multi-column join keys.
pair_key = Table.new({:city => ["lon", "nyc"], :team => ["core", "tools"], :floor => [1, 2]})
paired = staff.join(pair_key, [:city, :team])
check("multi-key join size", paired.size == 2)
check("multi-key join names", paired[:name] == ["ada", "barbara"])
check("multi-key join values", paired[:floor] == [1, 2])

# Empty right side.
empty_right = Table.new({:city => [], :country => []})
check("inner with empty right", staff.join(empty_right, :city).size == 0)
check("left with empty right", staff.join(empty_right, :city, :left).size == 5)
check("left with empty right fills", staff.join(empty_right, :city, :left)[:country] == [nil, nil, nil, nil, nil])

# String and Symbol join keys name the same column.
check("string join key", staff.join(cities, "city") == inner)

# ---------------------------------------------------------------- errors --

bad_kind = false
begin
  staff.join(cities, :city, :outer)
rescue error
  bad_kind = error.to_s.include?("supports :inner and :left")
check("bad join kind raises", bad_kind)

missing_left = false
begin
  staff.join(cities, :country)
rescue error
  missing_left = error.to_s.include?("has no column 'country'")
check("missing left key raises", missing_left)

missing_right = false
begin
  staff.join(cities, :team)
rescue error
  missing_right = error.to_s.include?("has no column 'team'")
check("missing right key raises", missing_right)

bad_agg = false
begin
  staff.aggregate(:nonsense)
rescue error
  bad_agg = error.to_s.include?("Unknown aggregation")
check("unknown aggregation raises", bad_agg)

bad_group = false
begin
  staff.group_by(:nope)
rescue error
  bad_group = error.to_s.include?("has no column 'nope'")
check("group_by missing column raises", bad_group)

bad_cumulative = false
begin
  staff.cumulative(:nonsense)
rescue error
  bad_cumulative = error.to_s.include?("Unknown cumulative aggregation")
check("unknown cumulative raises", bad_cumulative)

<< "ALL PASS table_group_join_spec ([passed.load()] checks)"
