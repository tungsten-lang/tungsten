# Syntax wishlist

Friction points hit while writing core/`.w` code — collected per the
builtin-port campaign's standing instruction to record (not change) syntax
pain. Each entry notes the workaround used today.

## From round 1 of the C-builtin ports (2026-07-18)

1. **Manual NaN-box rituals in primitive-class bodies.** Returning a raw
   `i64` from an `Integer`/`String` method requires hand-building the tag:
   `wvalue_from_bits((-1_688_849_860_263_936 | n) ## i64)` — copy-pasted in
   array.w, string_native.w, integer.w. Wish: `return n ## Int` (or an
   auto-boxing raw return on instance methods, like static raw-ABI methods
   already get).

2. **Sign-extending a 48-bit payload takes 3 lines.** `$value` masking then
   an explicit `if (a & 0x800000000000) != 0 / a -= 2^48` dance. Wish:
   `$int` (signed payload of the receiver) alongside `$value`.

3. **Typed parameters don't unbox.** A hot method body needs
   `i = count ## i64` on its own line per param. Wish:
   `-> drop(count ## i64)` performing entry unboxing (the machinery exists
   for `## i64` locals).

4. **Ternary vs `if` changes loop-var typing.** `i = count < 0 ? 0 : count`
   left `i` boxed (drop ran 1.6x slower); the equivalent `if` block kept it
   raw. Silent perf cliff — at minimum the two forms should type
   identically.

5. **String byte access requires the ccall boundary dance.** Reading bytes
   means `ccall("w_string_bytes_view", ...)` + `w_u8_live_data_ptr` +
   `raw_load_u8`, with the pointer-after-allocation ordering rule from
   base64.w. Wish: `s.byte(i)` / `s.each_byte` compiling to a raw load, and
   a `String.take_bytes(u8_arr)` that steals the buffer instead of copying.

6. **No way to reopen-and-test a live class quickly.** Scaffold files
   (core/string.w, core/numeric/int.w) parse fine but never dispatch;
   nothing at parse time distinguishes them from live ones
   (core/string_native.w, core/integer.w). Wish: a `# scaffold` pragma or
   loader warning when two registered files define the same class.

7. **Autoload trigger lists are hardcoded name tables in loader.w.** Every
   method migrated out of the runtime IC needs its name appended to a
   `call_name in (...)` list by hand; forgetting one produces "undefined
   method" only in programs that never touch a trigger method. Wish: the
   registry could be generated from the class files themselves (the
   manifest already knows class -> file).

## From rounds 5-12 of the C-builtin ports (2026-07-18)

8. **Inline-string construction is raw bit assembly.** Building a small
   result String in `$value` bits (swapcase, capitalize, chr, to_s, reverse,
   chars) means hand-assembling `tag | (len << 1) | (byte << (4 + 8*i))` with
   the magic tag `-1_970_324_836_974_592` (0xFFF9…) repeated in every method.
   Wish: a `String.from_bytes(b0, b1, …)` / `String.inline(bytes, len)`
   builder, or literal hex WValue tags (`0xFFF9_0000_0000_0000` as an i64
   literal) so the mask isn't a hand-computed signed decimal.

9. **Signed-decimal masks for bit ops.** Clearing a payload needs
   `& -281474976710641` (0xFFFF00000000000F as signed i64). Writing masks as
   negative decimals is unreadable and error-prone. Wish: unsigned/hex i64
   literals usable directly in `&`/`|` without the two's-complement hand-conversion.

10. **`u8[]`-to-steal costs a WArray header.** Building a byte buffer to hand
   to `w_string_take_byte_array` allocates a full WArray (header + slots), so
   it only wins when it replaces the C handler's own allocation; when C built
   in place on a bare malloc (String#reverse slab path), the Tungsten port
   had to delegate the tail to C. Wish: a bare-buffer type (owned `u8*` with
   length, no WArray header) for transient byte assembly.

11. **New ccall primitives must be hand-registered in the interpreter.** Any
   `ccall`/`ccall_nobox` name a core method uses must be added to a giant
   `when "name"` allowlist in interpreter.w or `-e`/eval dies with
   "Unsupported ccall" while the compiled path works (hit twice:
   w_string_take_byte_array, w_string_bytes_view). Wish: a single declarative
   whitelist table shared by the interpreter and lowering, or auto-derivation
   from the ccall sites.

12. **`0.0` is Decimal, `~0.0` is Float — silent in arithmetic.** A bench
   accumulator `t = 0.0` then `t += clock()-t0` died with "numeric + double"
   because bare `0.0` is a Decimal literal. Wish: clearer diagnostics, or a
   lint when a Decimal and Float mix in `+`.
