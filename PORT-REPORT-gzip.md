# PORT-REPORT-gzip: core/gzip.w (pure-Tungsten gzip/DEFLATE and Base64 text helpers)

Branch `port/gzip`, worktree `/Users/erik/tungsten-mf-port-gzip`. Status: skeleton; sections marked
PENDING are filled in as each measurement finishes.

## Files

| File | Lines | Role |
|---|---:|---|
| `core/gzip.w` | 1623 | `Gzip` (decompress, compress, encode_b64, decode_b64) and `GzipError` |
| `core/tungsten.w` | +2 | the two autoload lines (`Gzip`, `GzipError`) |
| `spec/core/gzip_spec.w` | 339 | 148 checks: golden fixtures, edge cases, errors, repeated-call memory |
| `spec/fixtures/gzip/` | 34 files | golden inputs made by Python's zlib (`make_fixtures.py`, 128 lines) |
| `bits/tungsten-metaflip/tools/gzb64.w` | 93 | command line: decode, encode, gunzip, gzip |
| `bits/tungsten-metaflip/spec/gzip_test.w` | 111 | 390 committed certificates, the tool, independent decoders |
| `bits/tungsten-metaflip/spec/gzip_bench.w` | 153 | decode check, decode timing, compression of the release tensors |
| `bits/tungsten-metaflip/spec/gzip_bench.py` | 143 | the Python side of the same |
| `PORT-BLOCKERS.md` | 87 | three runtime hazards met while writing the codec |

## API

PENDING

## Parity evidence

PENDING (a: decompression parity; b: compression round trips; c: determinism)

## Ratio and speed

PENDING

## Tests, runtimes, suggested shard

PENDING

## Deviations from the original behaviour

PENDING

## Blockers and workarounds

See `PORT-BLOCKERS.md`: typed arrays are never freed, `ByteArray#slice` is a zero-copy view,
`Base64.encode` leaves its output buffer allocated. Each has a workaround inside `core/gzip.w`.
