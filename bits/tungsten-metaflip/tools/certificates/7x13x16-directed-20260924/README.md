# Exact GF(2) 7×13×16 rank-962 tensor

This archive retains three full-tensor certificates: the 8×16×13/r1037
source, the 7×16×13/r964 intermediate, and the 7×16×13/r962 result. The
source is projected after two-pass basis mode 7 by deleting coordinate 6
of its first dimension, yielding rank 974. A 100M directed walk with nonce
2026092918 reaches rank 964. Basis mode 12 and a second 100M walk with
nonce 2026092924 reach rank 962. The checker verifies both projected
identities independently and can replay both walks byte-for-byte.

Against the pinned GF(2) block/Kronecker closure, r962 replaces r966 and
improves 17 shapes by 81 total rank units. This is a field-specific local
closure improvement. The public tracker listed rank 962 for 7×13×16 when
checked on 2026-09-24, so this is **not** claimed as a world record.

Run `python3 bits/tungsten-metaflip/tools/check_7x13x16_directed_20260924.py`
to check the tensors without external inputs. Pass `--catalog` with the
catalog revision whose SHA-256 is pinned in `manifest.json` to audit the
finite closure. Pass `--replay-walk` with a compiled
`tools/wide_rect_walk.w` binary to repeat both native walks. The repository's
`verify_tensor.rb` supplies the independent full-tensor check.
