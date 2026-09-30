# PORT-BLOCKERS (branch port/scheme)

Language and runtime defects met while porting the GF(2) scheme foundation library.
Each entry has a minimal repro (`bin/tungsten repro.w`, BIT_HOME unset or pointing at any
checkout; outputs from the toolchain at /Users/erik/tungsten, 2026-09-30), the workaround in
the port, and the marker to search for (`TODO(port)`). None of them blocks the port; all of
them cost time or force a workaround.

## 1. `String#to_i(16)` saturates at 2^63-1 instead of building a BigInt

```tungsten
<< "ffffffffffffffffffff".to_i(16)     # 9223372036854775807; the value is 2^80 - 1
<< "123456789012345678901234567890".to_i   # 123456789012345678901234567890 (decimal is exact)
```

No error, no promotion: every MFW1 mask wider than 63 bits silently becomes 2^63 - 1.
Workaround: `Metaflip:Gf2:Bits.hex_value` folds the digits into 64-bit limbs itself
(`lib/metaflip/gf2/bits.w`, `TODO(port)` above `hex_value`).

## 2. String concatenation loses an embedded NUL from `Integer#chr`

```tungsten
s = "a" + 0.chr + "b"
<< s.size          # 2  (expected 3)
<< "a\0b".size     # 3  (a literal keeps the NUL)
```

Building binary test data at run time with `+` and `0.chr` drops the NUL (the runtime seems
to treat the operand as a C string). Workaround: the tests spell such inputs as single string
literals (`"12 1\0 12"`), see `spec/verify_tensor_test.w`. The library itself never
concatenates bytes: it reads through `w_string_data_ptr` with an explicit length.

## 3. `run --interpret` does not coerce arguments to a typed `(i64)` parameter

```tungsten
-> clear_low(x) (i64) i64
  x & (x - 1)
<< clear_low((1 << 70) | 12)
```

Compiled prints `8` (the argument is wrapped to its low 64 bits on the way in, as every
other boxed -> i64 crossing does); `bin/tungsten run --interpret` prints
`1180591620717411303432` (the BigInt stays a BigInt). The first version of
`Bits.limb_positions` returned different answers in the two engines because of this.
Workaround: the helper only looks at the two 32-bit halves of its argument
(`bits.w`, `TODO(port)` above `limb_positions`).

## 4. The interpreter has no `w_value_free_w`, and no bounded-memory story for BigInt/typed arrays

```tungsten
x = i64[4]
ccall("w_value_free_w", x)     # run --interpret: "Unsupported ccall 'w_value_free_w' in interpreter"
```

Compiled Tungsten has no GC either, so the library frees its large temporaries with this
call (`Metaflip:Gf2:Bits.release`, rescued into a no-op under the interpreter). Under
`run --interpret` one parse of a 2.5 KB, rank-109 certificate costs ~45 MB, one dense gate
~40 MB, one sparse gate ~90 MB (RSS), and the golden tests reach 8 GB within seconds, so
`spec/gf2_scheme_test.w` and `spec/verify_tensor_test.w` are classified native. On
small inputs the library gives byte-identical answers in both engines.

## 5. `run --interpret`: a class method's `&block` parameter never receives the block

```tungsten
+ Foo
  -> .each_a(x, &block)
    block.call(x)
Foo.each_a(1) -> (i)
  << "got [i]"
```

Compiled prints `got 1`; the interpreter fails with `undefined method 'call' for nil`
(`block(x)` and `yield x` fail the same way, on class and instance methods alike).
Workaround: the library API returns Arrays (`Bits.positions`, `Scheme#terms`) and never
takes a block.
