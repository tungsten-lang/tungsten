# A zero-argument Decimal constructor must be rejected just like other arities;
# it cannot allocate an ordinary object for a packed/domain scalar facade.
<< Decimal.new()
