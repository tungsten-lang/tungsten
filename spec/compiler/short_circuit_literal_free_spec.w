# Free insertion versus short-circuit operands (ownership.w scope_pop).
#
# The right operand of `&&`/`||` lowers into its own block that the enclosing
# scope's pop does not dominate. A heap literal born there (a Decimal here)
# used to be released at the pop, and LLVM rejected the module with
# "Instruction does not dominate all uses". The scope's temps are now
# filtered by block dominance at the pop. This spec must compile and run;
# it also checks the values so a wrong release would surface as a bad result.
#
# Run: `bin/tungsten -o /tmp/scf spec/compiler/short_circuit_literal_free_spec.w && /tmp/scf`

-> check(name, got, want)
  if got.to_s() == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want
    exit 1

# Nested if with a Decimal literal on the right of && (the original report).
-> count_excused(rows, limit)
  count = 0
  r = 0
  while r < rows.size()
    row = rows[r]
    if row["a"] > limit
      if row["b"] <= limit && row["c"] >= 1.5
        count += 1
    r += 1
  count
rows = [{"a": 2.0, "b": 0.5, "c": 2.0}, {"a": 2.0, "b": 0.5, "c": 1.0}, {"a": 0.5, "b": 0.5, "c": 9.0}]
check("and.nested_if", count_excused(rows, 1.1), "1")

# Same shape at top level, which is where the report first failed.
row = {"a": 1.5, "b": 2.0}
limit = 1.1
excused = false
if row["a"] > limit
  if row["a"] <= limit && row["b"] >= 1.5
    excused = true
check("and.top_level_nested", excused, "false")
seen = false
if row["a"] > limit
  if row["a"] > limit && row["b"] >= 1.5
    seen = true
check("and.top_level_taken", seen, "true")

# `||` with the literal in the evaluated-only-sometimes operand.
-> any_small(values)
  hits = 0
  i = 0
  while i < values.size()
    v = values[i]
    if v > 0.0
      if v > 100.0 || v < 0.25
        hits += 1
    i += 1
  hits
check("or.nested_if", any_small([0.1, 0.5, 200.0, 0.2]), "3")

# Heap literals of other kinds inside the operand: a hash literal read only
# through w_hash_get is a tracked producer too.
-> hash_operand(keys)
  found = 0
  i = 0
  while i < keys.size()
    k = keys[i]
    if k != ""
      if k != "skip" && {"x": 1, "y": 2}[k] != nil
        found += 1
    i += 1
  found
check("and.hash_literal_operand", hash_operand(["x", "skip", "y", "z", ""]), "2")

# Loop churn so a wrong release would corrupt later results.
-> churn(n)
  acc = 0
  i = 0
  while i < n
    if i % 2 == 0
      if i % 3 == 0 && (i.to_f() / 3.0) >= 0.5
        acc += 1
    i += 1
  acc
check("and.churn", churn(60000), "9999")
