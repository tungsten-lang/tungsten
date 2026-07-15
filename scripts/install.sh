#!/bin/sh
# Tungsten installer — https://tungsten-lang.org
#
#   curl -fsSL https://tungsten-lang.org/install | sh
#
# Clones the repo and builds the self-hosted compiler from source. The build
# proves itself: stage 1 and stage 2 must emit byte-identical LLVM IR — and the
# binaries come out host-tuned (-march=native). Then `tungsten` is linked onto
# your PATH. Re-running updates an existing install.
#
# Environment:
#   TUNGSTEN_HOME  install prefix     (default: ~/.tungsten)
#   TUNGSTEN_BIN   symlink directory  (default: ~/.local/bin)
#   TUNGSTEN_REPO  git repo           (default: github.com/tungsten-lang/tungsten)

set -eu

TUNGSTEN_HOME="${TUNGSTEN_HOME:-$HOME/.tungsten}"
TUNGSTEN_BIN="${TUNGSTEN_BIN:-$HOME/.local/bin}"
TUNGSTEN_REPO="${TUNGSTEN_REPO:-https://github.com/tungsten-lang/tungsten}"

say()  { printf '\033[1;33mtungsten\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31mtungsten\033[0m %s\n' "$*" >&2; exit 1; }

# --- preflight ---------------------------------------------------------------
case "$(uname -s)" in
  Darwin|Linux) ;;
  *) fail "unsupported platform: $(uname -s) (Tungsten supports macOS and Linux; on Windows use WSL2)" ;;
esac
command -v clang >/dev/null 2>&1 || fail "clang is required (macOS: xcode-select --install; Debian/Ubuntu: apt install clang llvm)"
command -v git   >/dev/null 2>&1 || fail "git is required"
# Linux BLAS-backed numeric programs need the optional cblas.h + -lopenblas
# bridge. Probe the exact command used by the compiler, but do not block an
# ordinary bootstrap that never references @w_blas_. macOS uses Accelerate.
if [ "$(uname -s)" = Linux ]; then
  openblas_tmp="/tmp/tungsten-openblas-check-$$"
  if ! printf '#include <cblas.h>\nint main(void){return cblas_sdot(0, 0, 1, 0, 1) != 0.0f;}\n' \
       | clang -x c - -lopenblas -o "$openblas_tmp" >/dev/null 2>&1; then
    say "NOTE: BLAS-backed numeric programs require OpenBLAS (Debian/Ubuntu: apt install libopenblas-dev)"
  fi
  rm -f "$openblas_tmp"
fi

# --- clone + build -----------------------------------------------------------
if [ -d "$TUNGSTEN_HOME/.git" ]; then
  say "updating $TUNGSTEN_HOME"
  git -C "$TUNGSTEN_HOME" pull --ff-only
else
  say "cloning $TUNGSTEN_REPO -> $TUNGSTEN_HOME"
  git clone --depth 1 "$TUNGSTEN_REPO" "$TUNGSTEN_HOME"
fi
say "building the self-hosted compiler (stage 1 = stage 2 byte-identity is checked)"
# Run from TUNGSTEN_HOME: `tungsten build` is cwd-sensitive — from inside a
# directory with a Bitfile it builds that project, not the compiler.
( cd "$TUNGSTEN_HOME" && bin/tungsten build )

# --- link --------------------------------------------------------------------
mkdir -p "$TUNGSTEN_BIN"
ln -sf "$TUNGSTEN_HOME/bin/tungsten" "$TUNGSTEN_BIN/tungsten"
say "linked $TUNGSTEN_BIN/tungsten"

case ":$PATH:" in
  *":$TUNGSTEN_BIN:"*) ;;
  *) say "NOTE: add $TUNGSTEN_BIN to your PATH" ;;
esac

# --- hello -------------------------------------------------------------------
say "done. try it:"
printf '\n  tungsten start\n  echo '\''<< "Hello, W!"'\'' > hello.w\n  tungsten hello.w\n\n'
