# Date is a packed scalar. Generic object construction must not create an
# ordinary instance whose calendar accessors decode pointer bits.
<< Date.new()
