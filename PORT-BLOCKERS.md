# Port blockers and hazards found writing core/gzip.w

Nothing blocked the gzip port. Three runtime behaviours shaped the code and are
recorded here with minimal repros, because the next person to write a byte codec
in Tungsten meets them too. Each has a workaround in core/gzip.w; none was fixed
outside it (runtime/, compiler/ and the other core files are untouched).

## 1. Typed arrays are never freed

`u8[n]`, `i64[n]`, ... allocated in a method, a helper or a loop are not released
by the compiler's free insertion, however they are used (local, returned, passed
to a callee). Only an explicit `ccall("w_value_free_w", arr)` releases one.

```
i = 0
while i < 4000
  a = u8[100000]
  j = 0
  while j < 100000
    a[j] = 1
    j += 4096
  i += 1
```

Compiled `--release`: maximum resident set 25.9 MB after 200 iterations, 463.6 MB
after 4,000. Adding `ccall("w_value_free_w", a)` at the end of the loop body keeps
it flat at 2.9 MB.

Workaround (core/gzip.w): every scratch array (decode tables, hash chains, bit
buffers) is released before a call returns, through `Gzip.__release`, which
tolerates the tree-walking interpreter (it has no explicit free: the `ccall` is
rescued). A decompress or compress call then leaves only its result allocated;
the repeated-call test shows a flat resident set (5.8 MB after 1,000 calls of
decompress on a 130 KB output).

## 2. `ByteArray#slice(start, len)` is a zero-copy view

`spec/core/byte_array_slice_spec.w` says `slice` returns "a new ByteArray", but
`w_ic_array_slice` is an alias of `slice_view` (`w_array_view`): the result shares
the parent's buffer, and so does `a[i...j]`.

```
a = u8[4]
a[1] = 7
v = a.slice(0, 4)
v[1] = 9
<< a[1]        # prints 9
```

Views are registered against their parent in a hash table keyed by the parent's
address (`w_register_view`), and nothing removes an entry when the parent or the
view is freed. Combined with explicit frees (item 1) that is a use-after-free
waiting for an unlucky address reuse: a later array allocated at the parent's old
address inherits the stale entries, and `w_views_after_realloc` writes through
them when that array grows.

Workaround: core/gzip.w never slices. `Gzip.__sub(arr, lo, hi)` makes a real copy
(an 8-byte-word loop) wherever a sub-range is needed (trimming the result, the
CRC of one member of several, the header CRC).

## 3. `Base64.encode` leaves its output buffer allocated

`Base64.__encode` builds the encoded text in a `u8[]`, copies it into a String
with `w_string_from_byte_array` and never frees the array.

```
data = u8[12000]
i = 0
while i < 20000
  s = Base64.encode(data)
  ccall("w_value_free_w", s)     # the String is released here, the u8[] is not
  i += 1
```

Every call therefore leaks the encoded size (16 KB here). `Gzip.encode_b64` encodes
straight into its wrapped output buffer instead of going through `Base64`.

## Not blockers, but worth knowing

* `bin/tungsten script.w ARGS...` reads `--flag` and a bare `-` among the script's
  arguments as its own flags ("Unknown flag"); tools that take options in a
  wrapper-run script must use positional arguments (tools/gzb64.w does).
* The user-level `~/.gitignore` here ignores `*.gz`: the gzip fixtures are added
  with `git add -f`.
* Compiled and interpreted engines differ on unsigned 64-bit shifts: keep a bit
  buffer below 2^63 (mask after the wide refill) and both engines agree.
* `system(cmd)` returns a Boolean (true on exit status 0), not the status.
