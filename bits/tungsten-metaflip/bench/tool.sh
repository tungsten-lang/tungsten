#!/bin/sh
# Builds (once per source state) and runs a bench tool:  tool.sh metabench|metascore ARGS...
# Binaries live in $MB_BUILD (default ~/.tungsten/metaflip/bench-bin). The compiler is
# $TUNGSTEN, else `tungsten` on the PATH.
name=$1
shift
here=$(cd "$(dirname "$0")" && pwd)
bit=$(cd "$here/.." && pwd)
build=${MB_BUILD:-$HOME/.tungsten/metaflip/bench-bin}
compiler=${TUNGSTEN:-${METAFLIP_TUNGSTEN:-tungsten}}
mkdir -p "$build"
stamp=$(cat "$bit"/lib/metaflip/bench/*.w "$bit"/lib/metaflip/composition/packed.w "$bit/tools/$name.w" \
  | shasum -a 256 | cut -c1-16)
binary="$build/$name-$stamp"
if [ ! -x "$binary" ]; then
  (cd "$bit" && BIT_HOME="$bit/.." "$compiler" -o "$binary" "tools/$name.w" --release > "$build/$name-$stamp.log" 2>&1) || {
    cat "$build/$name-$stamp.log" >&2
    exit 1
  }
fi
exec "$binary" "$@"
