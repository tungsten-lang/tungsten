# AND: truthy LHS → return RHS value
<< true && "hello"

# AND: falsy LHS → return LHS, skip RHS
<< false && "never"

# OR: truthy LHS → return LHS, skip RHS
<< true || "never"

# OR: falsy LHS → return RHS value
<< false || "world"

# Nested
<< (true && true) && "nested"

# Short-circuit must skip side effects
x = 0
false && (x = 99)
<< x

y = 0
true || (y = 99)
<< y
