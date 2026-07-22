# Compiler answers (2026-07-22)

## Float literals — use `~1.0`

The old decimal-literal poison fixtures are **green** on both engines.
Prefer the tilde form for float literals:

```tungsten
lr = ~0.1
half = ~0.5
```

Koala’s `1.to_f / 10.to_f` style still works; `~` is the language’s
intended spelling.

## Bare tail array literal — **fixed**

```tungsten
-> after_block(xs)
  n = 0
  xs.each -> (x)
    n += 1
  [n, n]          # now works → [3, 3]
```

**Cause:** after a call-with-block, a next-line `[` was parsed as
**indexing** the call (`each(...)[n, n]`), so the comma was illegal inside
`[]` subscript.

**Fix:** treat call-with-block as a block node so `[` starts a new
statement (parser `is_block_node?`), plus same-line tight-postfix rule
for indexing.

## `type(instance)` — **fixed** (use `obj.class` too)

```tungsten
+ Box
  -> new(@x)
b = Box.new(1)
<< type(b)    # "Box" (was "Hash" on interpreter)
<< type({})   # "Hash"
<< b.class    # "Box"
```

**Cause:** interpreter objects are `{rt: :object, w_class: …}` hashes;
the `type` / `class` builtins called plain `type()` which reported the
Hash container.

**Fix:** both route through `interp.w_type_name`.

## Trait composition `with` — use **`is A`**

```tungsten
trait A
  -> a
    1

+ C
  is A          # correct spelling
  -> a
    1
```

`with A` inside a trait is **not** implemented (undefined method `with`).
Traits stay flat; compose with `is TraitName` on the class, or restate
methods. Koala already does this.

## Sibling-closure capture — **fixed**

```tungsten
-> f(values)
  s = 0
  i = 0
  values.each -> (v)
    s += i      # sums 0 three times → 0
  i = 1         # reassignment AFTER the each
  s
# Both engines: 0
```

**Cause:** WIRE `dead_store_elim` killed the capture flush of `i = 0`
because a later `i = 1` stored to the same slot with no intervening
`load_i64` of that slot. Loads through the captured inttoptr were
invisible to DSE, so the block read uninit garbage.

**Fix:**
1. Always flush the live capture value into the frame slot in
   `lower_block_closure` (with literal-assign recovery when bindings
   were cleared).
2. `dead_store_elim` treats `ptr_to_i64` as an address escape — stores
   to escaped slots are never DCE’d by a later overwrite.

## Float#to_s — **fixed**

`%g` → `%.17g` in `runtime/runtime.c` `w_to_s`.

```tungsten
x = 1.to_f / 3.to_f
<< x.to_s              # 0.33333333333333331
<< (x.to_s.to_f == x)  # true
```

## Class-side Tensor factories — **fixed** (interpreter ccalls)

`Tensor.zeros` failed with `Unsupported ccall 'w_array_new_aligned'`.
Interpreter now dispatches the Tensor/BLAS ccalls that exist in
`runtime/runtime.h` (`w_array_new_aligned`, `w_tensor_*`, `w_blas_*`).

```tungsten
use tensor
t = Tensor.zeros([2, 3])
<< t.shape.to_s   # [2, 3]
<< t.rank.to_s    # 2
```

## @ivar in blocks — works (use `-> new(@field)`)

```tungsten
+ C
  -> new(@items)
    @sum = 0
  -> total
    @items.each -> (x)
      @sum += x
    @sum
C.new([1, 2, 3]).total   # 6 on both engines
```

Prefer `-> new(@field)` for constructor field binding. Bare
`-> initialize` without the `@param` form does not install ivars.
Koala may still hoist defensively for older engines.

## Hash key order

No language change: when order matters, sort keys by `to_s` (koala
already does).
