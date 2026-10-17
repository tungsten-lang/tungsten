# spec: compiled-rejects -- Decimal.new is not a supported scalar constructor
# spec: interpreter-rejects -- Decimal.new is not a supported scalar constructor
# A zero-argument Decimal constructor must be rejected just like other arities;
# it cannot allocate an ordinary object for a packed/domain scalar facade.
<< Decimal.new()
