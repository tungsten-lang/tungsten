# Hash mutation during iteration follows the Ruby-compatible contract on every
# host: overwriting and deleting are allowed, adding a new key is rejected.
# Iteration bookkeeping must unwind when either the guard or the user block
# raises, so the hash remains mutable after rescue.

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

# String and Symbol keys with the same spelling remain distinct table entries.
key_kinds = {}
key_kinds["same"] = 1
key_kinds[:same] = 2
check("hash.key_kind.string", key_kinds["same"], 1)
check("hash.key_kind.symbol", key_kinds[:same], 2)
check("hash.key_kind.size", key_kinds.size(), 2)

# Char immediates are stable keys.
char_keys = {}
char_keys[:-A] = 7
char_keys[:-é] = 9
check("hash.char.ascii", char_keys[:-A], 7)
check("hash.char.unicode", char_keys[:-é], 9)

# Overwriting a live key is not a structural mutation and remains allowed.
overwrite = {a: 1, b: 2}
overwrite.each -> (key, value)
  overwrite[key] = value + 10
check("hash.each.overwrite.a", overwrite[:a], 11)
check("hash.each.overwrite.b", overwrite[:b], 12)

# Deleting a not-yet-visited key is allowed and removes it from this traversal.
deleted = {a: 1, b: 2, c: 3}
seen = []
deleted.each -> (key, value)
  seen.push(key)
  if key == :a
    deleted.delete(:b)
check("hash.each.delete.seen", seen, [:a, :c])
check("hash.each.delete.size", deleted.size(), 2)

# Adding a key is rejected, and the iteration guard unwinds through rescue.
added = {a: 1, b: 2}
add_rejected = false
begin
  added.each -> (key, value)
    added[:new_key] = 3
rescue error
  add_rejected = error.to_s().include?("during iteration")
check("hash.each.add.rejected", add_rejected, true)
check("hash.each.add.unchanged", added.has_key?(:new_key), false)
added[:after_rescue] = 4
check("hash.each.add.guard_unwound", added[:after_rescue], 4)

# A user exception must unwind the same guard too.
raised = {a: 1}
begin
  raised.each -> (key, value)
    raise "user block failure"
rescue error
  nil
raised[:after_user_error] = 2
check("hash.each.user_error_unwound", raised[:after_user_error], 2)

# Non-local return from a block uses the same cleanup stack as exceptions.
-> leave_hash_each(hash)
  hash.each -> (key, value)
    return "left"
  "missed"

returned = {a: 1}
check("hash.each.nonlocal_return", leave_hash_each(returned), "left")
returned[:after_return] = 3
check("hash.each.nonlocal_return_unwound", returned[:after_return], 3)

<< "hash mutation: all green"
