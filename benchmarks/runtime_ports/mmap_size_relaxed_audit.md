# Mmap#size relaxed-gate revisit — RETAIN

## Why revisit

The earlier isolated study rejected Mmap#size only because its retention gate
was `W/C <= 0.97`. Its best real-domain candidate measured approximately
`0.947` for ordinary inline sizes and `0.990` for exact overflow fallback in
long four-leg campaigns. Both are comfortably inside the current `<= 1.10`
policy. That study covered all signed-i64 header classes, exact Int/BigInt
representation, extra arguments, trailing blocks, close stability, and ABI
layout.

## Prepared production candidate

The small `core/mmap.w` facade now models WMmap's native view and implements
public `size` as:

1. raw signed `$size ## i64` field load;
2. one arithmetic `n >> 47` real-domain fit test;
3. cold canonical `w_int` fallback for negative/corrupt or enormous headers;
4. exact inline `0xFFFA | (n & 0xFFFFFFFFFFFF)` construction otherwise.

Real mmap lengths are nonnegative, so `(n >> 47) == 0` is exactly their
signed-i48 immediate domain. The fallback preserves the old native method for
every other signed-i64 header, including negative i48 values and `INT64_MIN`.

The native size IC alone is removed; all other Mmap IC rows remain and are
shifted locally. Compiler dispatch key `0x91`, targeted `File.mmap`/native-
return autoload, type discovery, and interpreter support are prepared because
the old study found that public removal without those pieces silently depended
on the global C IC. Other compiled `File.*` intrinsics do not load core/file;
an explicit `use core/file` imports the small `core/mmap.w` facade for
compatibility.

## Prepared validation

- Matched baseline/candidate public benchmark source and C ABI fixture. The
  benchmark deliberately does not redeclare WMmap's view: doing so would
  synthesize a later `size` accessor and shadow the production candidate.
- Sixteen signed-i64 header patterns with numeric equality, exact immediate
  bits, signed BigInt limb representation, and receiver stability.
- Surplus-argument and trailing-block parity against the native reference.
- Real mapping size before and after close.
- Separate ordinary inline and positive-overflow timing modes using per-thread
  CPU time. Each campaign uses alternating B/C/C/B and C/B/B/C legs, also
  alternates stratum order, and gates the median paired W/C ratio at 1.10.
- Separate no-use compiled specs for `File.mmap` and direct native-return
  autoload, plus tree-walker parity with the direct constructor exercised
  before File can load the class. They include retained `byte_at`, `[]`, and
  `close` behavior.
- WIRE contract: public field load + `ashr` + one comparison + cold `w_int` +
  mask/tag; the baseline bodyless declaration stays behind its native IC.

## Executed correctness and exactness

Fresh roots are based on `f62869bff0fc22fdc0a3179c82fb5da158d987d6`:

- `/tmp/tungsten-mmap-size-relaxed-baseline`
- `/tmp/tungsten-mmap-size-relaxed-candidate`

The runner uses one freshly rebuilt candidate compiler for both roots so
generated call sites are matched; that compiler is necessary because dispatch
key `0x91` did not exist in the installed bootstrap. CHECK_ONLY always runs
before timing and the exact release/LTO binaries that pass correctness are the
ones measured by the balanced campaign.

The fresh CHECK_ONLY gate passed before both campaigns:

- public candidate WIRE is exactly one `view_load_field`, `ashr`, comparison,
  cold `w_int`, mask, and tag-or; it has no dynamic method call or truthiness
  boxing;
- all sixteen signed-i64 headers match the C reference numerically and in
  exact immediate bits or signed BigInt limb representation, including both
  i48 boundaries, `INT64_MIN`, and `INT64_MAX`;
- receiver headers remain unchanged; surplus arguments, trailing blocks, and
  size-before/after-close behavior match the native reference;
- the C fixture statically pins every WMmap offset, size, and alignment;
- File.mmap-only and direct-native-only compiled autoload specs pass
  separately, so their whole-AST triggers cannot mask each other;
- direct native construction, source size, retained indexing, and close pass
  in the tree walker before File is referenced; and
- the retained native IC wrapper and name sequences are exactly baseline with
  only size removed.

The first WIRE attempt also caught a harness defect: redeclaring WMmap's view in
the benchmark synthesized a later `size` accessor and shadowed the production
method. The matched benchmark now reopens Mmap only for its uniquely named C
reference; `core/mmap.w` is the sole view owner.

## Balanced timing results

Each campaign independently rebuilt the common compiler, reran every gate
above, compiled fresh release/LTO baseline and candidate binaries, then ran ten
balanced pairs per stratum. Every pair summed B/C/C/B or C/B/B/C before taking
W/C; stratum order alternated too. Ordinary legs made 50,000,000 calls and
positive-overflow legs made 2,000,000 calls. Times are thread CPU ns/call.

### Campaign 1

| stratum | native median | source median | ratio of medians | paired median W/C | maximum pair W/C | maximum native leg | maximum source leg | gate |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| ordinary inline | 9.5939 | 9.0822 | 0.9467 | 0.9503 | 0.9658 | 9.8203 | 9.2603 | PASS |
| positive overflow | 25.6551 | 26.5606 | 1.0353 | 1.0263 | 1.2041 | 32.4578 | 31.8204 | PASS |

### Campaign 2

| stratum | native median | source median | ratio of medians | paired median W/C | maximum pair W/C | maximum native leg | maximum source leg | gate |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| ordinary inline | 9.5620 | 9.0613 | 0.9476 | 0.9501 | 1.0741 | 9.8783 | 11.0306 | PASS |
| positive overflow | 25.0998 | 26.6733 | 1.0627 | 1.0504 | 1.2812 | 28.3977 | 33.2079 | PASS |

Overflow allocates and frees a BigInt on every call, and its individual pairs
showed correspondingly large scheduler/allocator tails. Those maxima are
reported as diagnostics rather than hidden; the declared retention rule is
the paired median, and both independent overflow medians remain below 1.10.
The ordinary realizable-file domain is consistently about five percent faster.

## Artifact identities

- common bootstrap compiler: `0e69e9a9a60ae00112079a7f0e8dbe3892af7f8f1ba5696deb0b38312b2e6568`
- independently rebuilt campaign compilers (both byte-identical):
  `7a477e6777afd4b1b14a3c8128f102092fbc00e07d411b15e423ab207698f464`
- compiler sidemap (both):
  `aedd56a7fc69e2e363950304a47178b60a9913a8a5a6e26c3f15d21fab338c7b`
- emitted compiler LLVM (both byte-identical):
  `9374da339564f8c4d180bc3b8f5a83b431f5fb20b3ae9e50d3f9f2fb3eaf8899`
- release/LTO baseline binary (both):
  `2ab4a90da115831bc633eb1a6604b05804d380719e9fbfe71112f3dc07407468`
- release/LTO candidate binary (both):
  `5aad74e4747e53e25e064d8a17fef9f87caaaa0ea02509fb6a4ad1f4ef65c121`
- baseline/candidate WIRE (both campaigns):
  `f74d29bf208ee7b7384b30e584d7b3548d60ff36c570c9d8420dbbe3bbc72883` /
  `6811b805e1b6ee0c0ee531dabf5caa525fbad5ceca198e7fdf2611667d16093a`
- campaign result records:
  `b0fd3071baa3525c9ba05c3543c1606ab80b3793956ee1ea077715b7759de270` /
  `169f5788af895a19f5b2ff8c461e712f1a0f607d9d4db49523f8bf7bc4f61f93`

## Decision

**RETAIN Mmap#size in Tungsten.** Both declared strata pass the `W/C <= 1.10`
paired-median gate in two independent campaigns, with exact representation and
all public-behavior gates passing each time. Keep every other Mmap primitive in
the native IC table.
