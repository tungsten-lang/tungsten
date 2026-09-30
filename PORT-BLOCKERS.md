# Port blockers (branch port/support)

Language and standard-library defects met while porting the GF(2) support libraries
(`bits/tungsten-metaflip/lib/metaflip/gf2/`). Every entry has a minimal repro that was run
with `/Users/erik/tungsten/bin/tungsten` on 2026-09-30 (compiled engine unless stated).
None of them blocks the port; each was avoided in the library and the workaround is named.
`core/`, `compiler/` and `runtime/` were not touched.

## 1. Decimal values order wrongly in Array#sort, min, max, sort_by, and Array#<=>

Plain float literals are `Decimal`. `sort`, `min`, `max` and `sort_by` compare them by their
boxed bits, so the result is unsorted; scalar `<`, `<=>` are right. Cause found by the textx
work: `w_value_compare` (runtime/runtime.c, around line 54344) has no Decimal arm.

```
<< [0.5, 0.25].sort          # [0.5, 0.25]   (want [0.25, 0.5])
<< [0.5, 0.25].min           # 0.5           (want 0.25)
<< [~0.5, ~0.25].sort        # [0.25, 0.5]   (Float, the `~` literal, is fine)
<< [[0.5], [0.25]].sort      # unsorted
```

Workaround: `Textx.sort_by` / `sorted` refuse Decimal keys; `Textx.median_pair` sorts with an
explicit `<=>` block, which compares scalar Decimals correctly.

## 2. `*rest` together with two or more keyword parameters mis-binds

Positional arguments slide into the keyword slots and the given keywords are dropped.

```
+ Foo
  -> add(*names, type: nil, default: nil)
    "names=[names] type=[type] default=[default]"
<< Foo.new.add("--a", type: :int)                  # names=[] type=--a default=
<< Foo.new.add("--a", "-b", type: :int, default: 3) # names=[--a] type=-b default=3
```

One keyword parameter is fine. Workaround: `Cli#add` takes one primary name and `short:`.

## 3. An optional or keyword parameter before `&` steals the block (instance methods)

When the optional argument is omitted the trailing block is bound to it: "expected closure".
Class methods are not affected.

```
+ Foo
  -> run(label, fragment = nil, &)
    yield
Foo.new.run("x", "frag") -> 1     # ok
Foo.new.run("x") -> 1             # runtime error: expected closure
```

Workaround: block-taking instance methods have only required parameters (`Check#raises` and
`Check#raises_any` are two methods); block-taking class methods may use defaults.

## 4. Typed-signature instance method called from another instance method (implicit self)

Calls from outside the object work; a call from a sibling method passes shifted arguments:
"expected int, got nil".

```
+ W
  -> a(view, i) (u8[] i64) i64
    i + 2
  -> c(view, n)
    i = 0 ## i64
    while i < n
      i = a(view, i)
    i
v = u8[8]
<< W.new.c(v, 6)         # runtime error: expected int, got nil
```

Workaround: typed signatures only on class methods (`-> .name(...) (i64) i64`); instance methods
type their locals with `## i64`.

## 5. `String#to_i(16)` saturates at 2^63-1

Base 10 handles any length; base 16 (and presumably other bases) clamps. MFW1 factors are
hundreds of bits wide.

```
<< "c0ef6e5800000000".to_i(16)     # 9223372036854775807   (want 13902451898952187904)
<< "10000000000000000".to_i(16)    # 9223372036854775807   (want 18446744073709551616)
```

Workaround: `Textx.parse_hex` reads 60-bit chunks. `x.to_s(16)` on BigInt is correct.

## 6. Instance methods named `string`, `int`, `bool` or `integer` are hijacked

A call without receiver inside the class does not reach the method (it behaves like a
type-coercion builtin and answers nil). `hash`, `array`, `float`, `text`, `number` are fine.

```
+ W
  -> string(text)
    text.size
  -> run(key)
    string(key.to_s)
<< W.new.run("abc")     # runtime error: undefined method 'size' for nil
```

Workaround: the JSON writer's methods are `emit_string`, `emit_array`, ...

## 7. NUL bytes: `Integer#chr`, comparison and string literals

* `0.chr.size` is 0 (every other code point, surrogates included, gives UTF-8).
* `<=>`, `sort` and `min` compare with C-string semantics, so a string that starts with a NUL
  byte equals `""`, and `[nul_a, ""].sort` keeps `nul_a` first while `"" <=> nul_a` is -1.
* String literals have no `\x41` escape (`"\x41"` is four characters).

```
bytes = u8[2]
bytes[0] = 0
bytes[1] = 97
a = ccall("w_string_from_byte_array", bytes)    # the only way to build a NUL-holding String
<< 0.chr.size                       # 0
<< ("" <=> a)                       # -1
<< [a, ""].sort.first.size          # 2   (want 0)
```

Workaround: `Jsonx.nul_char` builds NUL through `w_string_from_byte_array`; `Jsonx.compare_text`
orders keys bytewise instead of using `<=>`. Python JSON keys with `\u0000` therefore sort right.

## 8. core `JSON.parse` (core/json.w)

Checked on 87 documents whose Python results are known (`spec/fixtures/gf2_support/json/parse_cases.jsonl`):
it agrees on 63 and differs on 24. Right: integers of any size, key order, repeated keys (last value, first
position), and the double for every float (122,740 valid JSON decimals, bit-identical to Python's `float()`).
Wrong:

* `\uXXXX` escapes are not decoded: `JSON.parse("\"\\u00e9\"")` is `"u00e9"`; `\b` and `\f` become `b` and `f`;
  surrogate pairs become `ud83dude00`.
* an invalid escape (`"a\x"`), a raw control character in a string, leading zeros (`01`), `1.`,
  and trailing garbage (`1 2`, `[1] x`, `truex`, `nulll`) are accepted silently.
* `NaN`, `Infinity`, `-Infinity` (which Python accepts) raise.
* errors carry no position.

It is also 5x (matmulcatalog table, 131 ms vs 26 ms) to 13x (67 FMM scheme files, 1.55 s vs 0.12 s) slower than
`Jsonx.loads`. Not fixed in core (out of scope); `Jsonx.loads` replaces it in the toolchain.

## 9. Parser: a parenthesised ternary as the left operand of `+` or `-`

`(cond ? a : b) - 2` silently drops the `- 2` (a wrong result, no error); `(cond ? a : b) + 2` is a parse error.
`(a + 1) + 2` and `(c || "d") + "x"` are fine.

```
w = 5
x = (w > 3 ? w : 80) - 2
<< x                       # prints 5 (want 3)
y = (w > 3 ? w : 80) + 2   # error: Unexpected token PLUS(+)
```

Workaround: assign the ternary to a local first.

## 10. Parser: a bare `return if cond` followed by more statements does not parse

```
-> f(x)
  return if x == 0
  x + 1
<< f(1)                    # error: Expected 9, got ID(x)
```

`return nil if x == 0` works. All new code writes `return nil if ...`.

## 11. Compiled: an instance method with nine or more parameters (some keyword) miscompiles

```
+ K
  -> a(name, b: nil, c: nil, d: nil, e: nil, f: nil, g: nil, h: nil, i: nil)
    "name=[name] i=[i]"
<< K.new.a("x", i: 5)      # prints name=<object> i=5   (want name=x i=5); sometimes exit 139
```

Seven keyword parameters (eight in all) work, and 11 positional-only parameters also work.
Workaround: `Cli#add(name, opts = {})` takes an options Hash.

## 12. Interpreter (`bin/tungsten run --interpret`) differences that keep the new tests native-only

* a method declared with `&` does not receive a trailing block: `t.run ->` + block gives "no block given"
  (`Check#raises` and `Check#raises_any` therefore need the compiled engine);
* `__DIR__` inside a `use`d file is the main file's directory ("." for a relative main path), not the file's own;
* negative doubles cannot be boxed: `wvalue_from_bits(-4631220381811107430 ## i64)` gives "unsupported packed WValue",
  so `Floatx.parse("-0.1")` dies interpreted;
* `Array#unshift` is undefined.

## 13. Smaller findings

* `Array#first(n)` ignores `n`: `[5, 6, 7, 8].first(2)` prints 5 (`take` and `slice` work).
* Hash keys that are Arrays hash by identity: `h = {}; h[[1, 2]] = :a; h[[1, 2]] = :b; h.size` is 2.
  `Textx.tally`, `setdefault`, `push_to`, `add_to` and `group_by` refuse Array keys.
* `Real#<=>` aborts on unlike operands instead of answering nil:
  `-> order(a, b)` with `a <=> b` and `order(1, "a")` dies with "expected int, got string" (core/numeric/real.w:8).
* `fn` is reserved and cannot be a variable name.
* Regex literals in the compiled engine: `\d` and `\w` never match (`"42" =~ /^\d+$/` is false), `(?:...)` is rejected at
  run time ("invalid regex ...: repetition-operator operand invalid"), and `String#match` is undefined (`=~` answers a
  Boolean). Explicit classes, capturing groups, alternation and optional groups work:
  `"4x5x6_m9_ZT.json" =~ /^([0-9]+)x([0-9]+)x([0-9]+)_m([0-9]+)(_[^\/]*)?_(ZT|Z|Q)\.json$/` is true. The originals' `re` patterns
  (FMM ring names, catalogue file names, lineage references) need this rewrite; no support library covers regex.
* `Array#last(n)` ignores `n`; `Array#copy` needs an argument; `Array#insert` is missing; `String#split(sep, limit)`
  ignores the limit; `nil.nil?` is undefined when compiled.
* An explicit `use core/base64` (or another core file that the autoloader also provides) inside a worktree
  resolves to the worktree's `core/`, while the autoloader loads the main checkout's: "duplicate definition
  of 'base64_encode'". Use the autoload for Base64, File and JSON; `use core/crypto/crc32` and
  `core/crypto/sha256` are safe.

## 14. Closures, splats, unwired File builtins (from the fsx/gitx work)

* The parameter of an outer block, captured by a closure inside an `if` branch that has an `else`, is corrupted
  (it works without the `else`, or with the closure outside the `if`):
  ```
  -> with_block(label, &)
    yield
    label
  -> run(rows)
    rows.each -> (row)
      if row[1] == "!"
        with_block("y") ->
          << "inner [row[0]]"
      else
        << "else: [row[0]]"
  run([["1", "x"], ["2", "!"]])     # runtime error: undefined method '[]' for Object
  ```
* A literal bracket in a string inside a block interpolates an undefined name and the compiled program dies with a
  segmentation fault (exit 139) instead of a diagnostic:
  ```
  -> run(label, &)
    yield
    label
  run("a") ->
    x = "[ab]*"      # exit 139
    << x
  ```
* There is no splat at the call site: `two(*[7, 8])` passes the array as one argument
  ("'two' takes 2 arguments, got 1").
* `"abc".include?("\0")` is true (a NUL needle counts as the empty string); `index("\0")` is right.
* `core/file.w` declares `File.basename`, `dirname`, `extname`, `realpath`, `readlink`, `symlink`, `symlink?`,
  `file?` and `File.open`, but the compiled runtime has no builtin behind them
  (`File.basename("/a/b.txt")` is "undefined method 'file_basename' for File"). `Fsx` supplies path arithmetic
  in Tungsten and `Fsx.append` through `__w_append_file`.

## 15. Design limits worth knowing (not defects)

* No garbage collector: a parsed tree is never freed. A 15 MB scheme file leaves about 30 MB behind, so
  the bulk tools call `Jsonx.release(tree)` (measured: 338 MB after 12 parses without it, 60 MB with it).
* The launcher intercepts `-h`, `--help`, `-v` and unknown flags that follow the `.w` file: run a tool as
  `bin/tungsten run tool.w -- --help` (the `--` is dropped before the program sees its arguments); a binary built
  with `-o` receives its arguments untouched.
* `capture` returns stdout only, drops the exit status and cuts the text at the first NUL byte; `File.open`
  is unwired (`file_open` undefined); `Procx` and `Fsx.append` (through `__w_append_file`) work around both.
||||||| 1010f8c0e

---

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
