# Numeric arity methods have no named parameter nodes. The C bootstrap must
# still allocate argument locals and resolve @1/@2 to those synthetic slots.
-> combine/2
  @1 * 10 + @2

-> identity/1
  @1

puts combine(4, 2)
puts identity(9007199254740991)
