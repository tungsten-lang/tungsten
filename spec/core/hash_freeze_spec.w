# Hash freezing is visible through aliases, transitive for nested hashes,
# and rejects writes even when a delete or merge would otherwise be a no-op.
-> check(label, condition)
  if !condition
    raise "FAIL " + label

nested = {"answer" => 42}
h = {"nested" => nested, "kept" => 7}
alias_h = h
check("initially mutable", !h.frozen?())
h.freeze()
check("frozen", h.frozen?())
check("alias frozen", alias_h.frozen?())
check("nested frozen", nested.frozen?())
check("lookup", h["kept"] == 7)
check("membership", h.has_key?("nested"))
h.freeze()

failures = 0
begin
  alias_h["kept"] = 99
rescue err
  check("overwrite error", err.to_s().include?("frozen"))
  failures += 1
begin
  h["added"] = 1
rescue err
  failures += 1
begin
  h.delete("kept")
rescue err
  failures += 1
begin
  h.delete("absent")
rescue err
  failures += 1
begin
  h.merge!({})
rescue err
  failures += 1
begin
  nested["answer"] = 0
rescue err
  failures += 1
check("all mutations rejected", failures == 6)
check("unchanged", h.size == 2 && h["kept"] == 7 && nested["answer"] == 42)
merged = h.merge({"new" => 3})
check("nonmutating merge", !merged.frozen?() && merged["new"] == 3)
cycle = {}
cycle["self"] = cycle
cycle.freeze()
check("cycle", cycle.frozen?())
<< "hash freeze: PASS"
