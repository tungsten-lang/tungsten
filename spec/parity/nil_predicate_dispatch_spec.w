# nil? must work through dynamic dispatch without an explicit Object import.
# User equality and inheritance must not change the nil predicate.
+ NilPredicateProbe
  -> ==(other)
    true

+ NilPredicateChild < NilPredicateProbe
  -> marker
    1

values = [nil, false, true, 0, "", :value, [], {}, NilPredicateProbe.new, NilPredicateChild.new, NilPredicateProbe]
i = 0
while i < values.size
  actual = values[i].nil?
  raise "nil predicate mismatch at [i]" if actual != (i == 0)
  i += 1
<< "PASS nil predicate dispatch ([i] values)"
