#!/usr/bin/env bash
set -euo pipefail

if (( $# != 0 )); then
  echo "build.sh takes no arguments" >&2
  exit 2
fi

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# In a staged submission this script is at the source-tree root.  In a
# development checkout it remains beside the other competition wrappers.
if [[ -x "$script_dir/bin/tungsten" &&
      -f "$script_dir/bits/tungsten-wassat/bin/wassat.w" ]]; then
  source_root="$script_dir"
else
  source_root="$(CDPATH= cd -- "$script_dir/../../.." && pwd)"
fi

tungsten="$source_root/bin/tungsten"
entrypoint="$source_root/bits/tungsten-wassat/bin/wassat.w"
output="$script_dir/wassat"
temporary="$script_dir/.wassat-build.$$"

if [[ ! -x "$tungsten" || ! -f "$entrypoint" ]]; then
  echo "incomplete Wassat source tree: expected bin/tungsten and $entrypoint" >&2
  exit 1
fi

cleanup() {
  rm -f -- "$temporary" \
    "$temporary.base.sidemap" "$temporary.cu" "$temporary.metal" \
    "$temporary.sidemap"
}
trap cleanup EXIT HUP INT TERM

# A fresh source submission contains no host binary.  Tungsten's C bootstrap
# builds the compiler from source without downloading dependencies.
if [[ ! -x "$source_root/bin/tungsten-compiler" ]]; then
  # The bootstrap driver's faster C-native parser intentionally emits a
  # non-fixed-point stage-1 compiler. That compiler is sufficient to build
  # stage 2, but is not general enough to compile current Wassat directly
  # (notably block-yield lowering). The canonical parser produces a source-
  # bootstrap compiler that can compile this submission without Ruby/stage 2.
  (ulimit -s 131072 2>/dev/null || true
   TUNGSTEN_BOOTSTRAP_DISABLE_ZSTD=1 TUNGSTEN_C_FAST_PARSE=0 \
     TUNGSTEN_ROOT="$source_root" "$tungsten" bootstrap)
fi

(ulimit -s 131072 2>/dev/null || true
 TUNGSTEN_ROOT="$source_root" "$tungsten" compile "$entrypoint" \
   --out "$temporary" --release --lto --intern raw)

if [[ ! -x "$temporary" ]]; then
  echo "Wassat compilation did not produce an executable" >&2
  exit 1
fi

mv -f -- "$temporary" "$output"
for suffix in .base.sidemap .cu .metal .sidemap; do
  if [[ -f "$temporary$suffix" ]]; then
    mv -f -- "$temporary$suffix" "$output$suffix"
  fi
done

trap - EXIT HUP INT TERM
echo "built $output"
