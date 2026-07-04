# Regression: an earlier inlined iterator leaks its loop var `item` into the
# enclosing slots; a later zero-param block must still bind `item` as its own
# implicit element param (params shadow captures), not read the stale value.
order = [10, 20, 30]
order.each -> (item)
  x = item
totals = order.map -> item * 2
<< totals
