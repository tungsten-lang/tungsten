# Regression spec for the writable native-data view-field path behind
# neg!/abs! (7b19a1e): BigInt keeps its sign in the `- data` header field,
# so a bang method is a checked view-field WRITE (w_native_data_field_set
# compiled, the interpreter's native_data_field_writable? bridge otherwise)
# and every predicate is a view-field READ. This spec pins write→read
# coherence through that machinery on both engines.

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

# --- read path: predicates are $-field reads on the native header ---
pos = (1 << 200) + 12346
neg = 0 - pos
check("read.positive?", pos.positive?.to_s(), "true")
check("read.negative?", neg.negative?.to_s(), "true")
check("read.zero?", pos.zero?.to_s(), "false")
check("read.even?", pos.even?.to_s(), "true")
check("read.odd?", (pos + 1).odd?.to_s(), "true")
# even?/odd? read $limb0 through the view; sign must not disturb parity
check("read.neg_even?", neg.even?.to_s(), "true")

# --- write path: neg!/abs! are single view-field writes ---
x = (1 << 200) + 999
x.neg!
check("write.neg_bang_sign", x.negative?.to_s(), "true")
check("write.neg_bang_value", x.to_s(), (0 - ((1 << 200) + 999)).to_s())
x.neg!
check("write.neg_bang_involution", x.to_s(), ((1 << 200) + 999).to_s())
x.neg!
x.abs!
check("write.abs_bang", x.positive?.to_s(), "true")

# write→read coherence in the 17..23-limb capacity blind spot
wide = (1 << (64 * 19 - 5)) + 424242
wide.neg!
check("write.wide_sign", wide.negative?.to_s(), "true")
check("write.wide_roundtrip", wide.to_s().to_i() == wide, true)
wide.abs!
check("write.wide_abs", wide.positive?.to_s(), "true")

# arithmetic must observe the written header, not a stale cached sign
y = (1 << 300) + 77
y.neg!
check("write.arith_sees_write", (y + ((1 << 300) + 77)).to_s(), "0")
check("write.mul_sees_write", (y * -1).to_s(), ((1 << 300) + 77).to_s())

# mutation is visible through aliases (documented bang contract)
a = (1 << 128) + 5
b = a
a.neg!
check("write.alias_visible", b.negative?.to_s(), "true")

<< "bigint_view_field_write_spec: all checks passed"
