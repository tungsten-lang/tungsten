# Array and hash operations.
#
# Run: `bin/tungsten -o /tmp/ah spec/core/arrays_hashes_spec.w && /tmp/ah`

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

# -- Array index / mutation --
arr = [10, 20, 30]
check("arr.index0", arr[0], 10)
check("arr.index2", arr[2], 30)
check("arr.neg1", arr[-1], 30)
arr[1] = 99
check("arr.set", arr[1], 99)
check("arr.size", arr.size, 3)

# -- push / pop / first / last --
xs = [1, 2]
xs.push(3)
check("arr.push", xs.size, 3)
check("arr.last", xs.last, 3)
check("arr.first", xs.first, 1)
popped = xs.pop()
check("arr.pop.val", popped, 3)
check("arr.pop.size", xs.size, 2)

# -- include? / empty? / sum / min / max --
nums = [5, 3, 1, 4, 2]
check("arr.include.true", nums.include?(4), true)
check("arr.include.false", nums.include?(9), false)
check("arr.empty.false", nums.empty?, false)
check("arr.empty.true", [].empty?, true)
check("arr.sum", nums.sum, 15)
check("arr.min", nums.min, 1)
check("arr.max", nums.max, 5)

# -- sort / join --
sorted = nums.sort
check("arr.sort.0", sorted[0], 1)
check("arr.sort.4", sorted[4], 5)
check("arr.sort.orig", nums[0], 5)
check("arr.join", sorted.join(","), "1,2,3,4,5")

# -- map / select (block form used by other compiled specs) --
doubled = nums.map -> item * 2
check("arr.map.0", doubled[0], 10)
check("arr.map.sum", doubled.sum, 30)

evens = nums.select -> item % 2 == 0
check("arr.select.size", evens.size, 2)
check("arr.select.sum", evens.sum, 6)

# -- reduce via accumulator cell (init + each) --
total = [0]
nums.each -> total[0] = total[0] + item
check("arr.reduce_each", total[0], 15)

# -- concat --
a = [1, 2, 3]
b = [4, 5]
joined = a.concat(b)
check("arr.concat.size", joined.size, 5)
check("arr.concat.first", joined[0], 1)
check("arr.concat.last", joined[4], 5)
check("arr.concat.orig_a", a.size, 3)

# -- Hash string keys --
h = {"name" => "alice", "age" => 30}
check("hash.str.name", h["name"], "alice")
check("hash.str.age", h["age"], 30)
h["city"] = "paris"
check("hash.str.set", h["city"], "paris")

# -- Hash symbol / keyword-style keys --
person = {name: "Alice", age: 30, city: "Portland"}
check("hash.sym.name", person[:name], "Alice")
check("hash.sym.age", person[:age], 30)
check("hash.sym.city", person[:city], "Portland")
check("hash.sym.size", person.size, 3)
check("hash.sym.missing", person[:nope] == nil, true)

# Mutate symbol-key hash
person[:age] = 31
check("hash.sym.update", person[:age], 31)
person[:job] = "engineer"
check("hash.sym.insert", person[:job], "engineer")
check("hash.sym.size_after", person.size, 4)

<< "arrays_hashes_spec: all checks passed"
