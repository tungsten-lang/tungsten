# Dogfood for `var$field` — postfix view-decl field access on an explicit
# receiver. Generalizes the implicit-`__self` `$field` accessor: any named
# variable holding a runtime-backed view class can read its `- data` struct
# fields inline. Array's WArray layout (core/array.w) has u8 ebits@1 and
# u32 size@8, so `a$size` / `a$ebits` GEP+load straight off the object
# pointer with no method dispatch.
#
# Run: `bin/tungsten -o /tmp/vfv spec/compiler/view_field_var_spec.w && /tmp/vfv`

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()

a = [10, 20, 30]
check("array size via a$size", a$size, 3)
check("array ebits via a$ebits", a$ebits, 65)

b = [1, 2, 3, 4, 5, 6, 7]
check("second receiver b$size", b$size, 7)
check("view-field usable in arithmetic", a$size + b$size, 10)

# $field-on-self REGRESSION: Array#each reads `$size` on the implicit
# __self internally — the explicit-receiver path must not disturb it.
total = 0
a.each -> (x)
  total += x
check("$field-on-self (Array#each) still works", total, 60)

# Fixed inline u8[N] fields use field_offset + index (no hidden bounds branch)
# and stay raw through integer expressions. WNetAddr.bytes begins at offset 4.
ip = IPv6.parse("2001:db8::1") ## IPv6
check("fixed inline byte first", ip$bytes[0], 0x20)
check("fixed inline byte last", ip$bytes[15], 1)
check("fixed inline bytes remain raw", (ip$bytes[0] << 8) | ip$bytes[1], 0x2001)
