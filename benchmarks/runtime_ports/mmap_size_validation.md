# Mmap#size independent validation — rejected

## Decision

Keep the C IC. No source candidate cleared `W/C <= 0.97` in both the ordinary
inline-Int and signed-i64/BigInt strata. Production was not modified.

## ABI and semantics

- Runtime dispatch key is `0x91`: `0x80 | W_TYPE_MMAP(17)` for a
  `W_SUBTAG_GENERIC` object.
- `WMmap` is 24 bytes, aligned to 8, with `type@0`, `closed@1`, `pad@2`,
  `data@8`, and `size@16`. The source view omits the implicit type byte and
  therefore loads its declared `size@15` at effective C offset 16.
- A 16-value fixture covered zero, small values, both signed-i48 boundaries,
  adjacent overflows, negative values, and `INT64_MIN/MAX`. V1–V6 matched the
  C handler in value, Int-vs-BigInt representation, and exact inline bits.
- Extra arguments were ignored by both paths. A trailing block followed the
  language's no-block-method passthrough semantics: an 11-byte mapping ran it
  11 times through both paths.
- `close` leaves `WMmap.size` intact; both paths returned 11 before and after
  closing a real 11-byte mapping.

## Candidate bodies

- V1: direct raw-i64 return, boxed by the compiler with `w_int`.
- V2: two explicit signed bounds plus inline i48 boxing.
- V3: sign-extension fit test, inline i48 boxing, `w_int` slow path.
- V4: V3 with the common path arranged as fallthrough.
- V5: real-domain test `(n >> 47) == 0`; negative synthetic headers use
  `w_int`, while every possible nonnegative real inline length is inlined.
- V6: V5 with the common path arranged as fallthrough.

All slow paths preserve exact signed-i64 BigInt semantics, including
`INT64_MIN`.

## Timing

The release benchmark used unique source names with identical dynamic dispatch
shape, alternating order, identical checksums, and a short-chunk interleaved
mode to reduce scheduler/frequency drift.

| candidate | inline W/C | overflow W/C |
|---|---:|---:|
| V1 | 0.953014 | 0.987081 |
| V3 | 0.953187 | 0.977445 |
| V4 | 0.956162 | 0.983216 |
| V5 | 0.948592 | 0.988818 |
| V6 | 0.947895 | 0.996834 |

The longer V6 repeat (12 samples, 75M inline / 7.5M overflow per leg) gave
0.947107 inline and 0.989924 overflow. The earlier V3 long repeat gave
0.962636 inline and 0.992345 overflow. Allocation/free cost dominates the
validation saved by the source field read on the overflow path.

## Loading and interpreter findings

- `core/tungsten.w` registers neither `File` nor `Mmap` for autoload.
- Bare compiled `File.mmap("VERSION").size` emits no Mmap type-class
  registration and works today only because the C IC is globally installed.
- The tree walker cannot currently construct a mapping through `File.mmap`,
  has no Mmap `$size` field bridge, and reports generic WMmap values as
  `Unknown`.
- A future retry needs a targeted `File.mmap -> core/file` loader trigger and
  explicit interpreter support before removing the C IC.

Because performance failed first, no public source tree, ASan/fixed-point
campaign, or native-IC removal was warranted. The full isolated artifacts are
under `/tmp/tungsten-mmap-size`.
