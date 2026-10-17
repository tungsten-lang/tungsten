# spec: compiled-rejects -- Decimal.new is not a supported scalar constructor
# spec: interpreter-rejects -- Decimal.new is not a supported scalar constructor
# Decimal values come from literals and conversions. The historical bodyless
# `Decimal.new(scale)` declaration constructed a malformed ordinary object.
<< Decimal.new(2)
