# Indexed access to BigInt's u64[] limb tail — the compiled strided
# element load/store and the tree walker's w_native_data_elem bridges must
# agree. Methods are added by reopening BigInt, exactly how kernel bodies
# in core/numeric/big_int.w read and write limbs.

+ BigInt
  -> __spec_limb_low16(i)
    ($limbs[i] ## u64) & 65535

  -> __spec_poke_limb(i, v)
    $limbs[i] = v
    self

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

# 2^64 + 5 has limbs [5, 1]
x = 2 ** 64 + 5
check("read.limb0", x.__spec_limb_low16(0), 5)
check("read.limb1", x.__spec_limb_low16(1), 1)

# Write limb 0 of an owned value; the value changes accordingly and the
# neighbor limb is untouched (2^64 + 9)
x.__spec_poke_limb(0, 9)
check("poke.value", x.to_s(), (2 ** 64 + 9).to_s())
check("poke.limb0", x.__spec_limb_low16(0), 9)
check("poke.limb1_stable", x.__spec_limb_low16(1), 1)

# Multi-limb read across a wider value: 2^192 has limbs [0,0,0,1]
y = 2 ** 192 + 3
check("wide.limb0", y.__spec_limb_low16(0), 3)
check("wide.limb3", y.__spec_limb_low16(3), 1)

<< "bigint_limb_index_spec: all checks passed"
