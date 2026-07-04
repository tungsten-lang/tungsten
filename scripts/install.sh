#!/bin/sh
# Tungsten installer — https://tungsten-lang.org
#
#   curl -fsSL https://tungsten-lang.org/install | sh
#
# Prefers a prebuilt, portable release binary (fast: no bootstrap). Falls back to
# cloning the repo and building the self-hosted compiler from source (the build
# proves itself: stage 1 and stage 2 must emit byte-identical LLVM IR). Either
# way, `tungsten` is linked onto your PATH. Re-running updates an existing install.
#
# Environment:
#   TUNGSTEN_HOME         install prefix     (default: ~/.tungsten)
#   TUNGSTEN_BIN          symlink directory  (default: ~/.local/bin)
#   TUNGSTEN_REPO         git/releases repo  (default: github.com/tungsten-lang/tungsten)
#   TUNGSTEN_FROM_SOURCE  set to 1 to skip the prebuilt binary and build from source

set -eu

TUNGSTEN_HOME="${TUNGSTEN_HOME:-$HOME/.tungsten}"
TUNGSTEN_BIN="${TUNGSTEN_BIN:-$HOME/.local/bin}"
TUNGSTEN_REPO="${TUNGSTEN_REPO:-https://github.com/tungsten-lang/tungsten}"

say()  { printf '\033[1;33mtungsten\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mtungsten\033[0m %s\n' "$*" >&2; }
fail() { printf '\033[1;31mtungsten\033[0m %s\n' "$*" >&2; exit 1; }

# --- preflight ---------------------------------------------------------------
case "$(uname -s)" in
  Darwin|Linux) ;;
  *) fail "unsupported platform: $(uname -s) (Tungsten supports macOS and Linux; on Windows use WSL2)" ;;
esac
command -v clang >/dev/null 2>&1 || fail "clang is required (macOS: xcode-select --install; Debian/Ubuntu: apt install clang llvm)"

# --- pick the release asset for this OS / arch / CPU tier --------------------
# x86-64 ships two tiers: v3 (AVX2, newer CPUs) and v2 (the safe floor). arm64
# ships one baseline. Names match .github/workflows/release.yml.
release_asset() {
  _os=""; _arch=""
  case "$(uname -s)" in Darwin) _os=darwin ;; Linux) _os=linux ;; esac
  case "$(uname -m)" in
    arm64|aarch64) _arch=arm64 ;;
    x86_64|amd64)  _arch=x86_64 ;;
    *) return 1 ;;
  esac
  _name="tungsten-${_os}-${_arch}"
  if [ "$_arch" = "x86_64" ]; then
    if cpu_has_avx2; then _name="${_name}-v3"; else _name="${_name}-v2"; fi
  fi
  printf '%s' "$_name"
}

cpu_has_avx2() {
  if [ -r /proc/cpuinfo ]; then
    grep -qw avx2 /proc/cpuinfo
  else
    # macOS x86_64
    sysctl -n machdep.cpu.leaf7_features 2>/dev/null | tr 'A-Z' 'a-z' | grep -q avx2
  fi
}

# --- try the prebuilt binary -------------------------------------------------
# Returns 0 on a verified install, 1 to signal "fall back to source".
install_prebuilt() {
  command -v curl >/dev/null 2>&1 || return 1
  asset="$(release_asset)" || return 1
  url="${TUNGSTEN_REPO}/releases/latest/download/${asset}.tar.gz"

  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN 2>/dev/null || true
  say "fetching prebuilt ${asset}"
  curl -fsSL "$url" -o "$tmp/${asset}.tar.gz" || { rm -rf "$tmp"; return 1; }

  # Verify SHA256 when the checksum sidecar is available (best-effort: skip with
  # a warning if neither shasum nor sha256sum exists).
  if curl -fsSL "${url}.sha256" -o "$tmp/${asset}.tar.gz.sha256" 2>/dev/null; then
    if command -v shasum >/dev/null 2>&1; then
      ( cd "$tmp" && shasum -a 256 -c "${asset}.tar.gz.sha256" ) >/dev/null 2>&1 \
        || { warn "checksum mismatch — falling back to source"; rm -rf "$tmp"; return 1; }
    elif command -v sha256sum >/dev/null 2>&1; then
      ( cd "$tmp" && sha256sum -c "${asset}.tar.gz.sha256" ) >/dev/null 2>&1 \
        || { warn "checksum mismatch — falling back to source"; rm -rf "$tmp"; return 1; }
    else
      warn "no shasum/sha256sum — skipping checksum verification"
    fi
  fi

  tar -xzf "$tmp/${asset}.tar.gz" -C "$tmp" || { rm -rf "$tmp"; return 1; }
  [ -x "$tmp/${asset}/bin/tungsten-compiler" ] || { rm -rf "$tmp"; return 1; }

  rm -rf "$TUNGSTEN_HOME"
  mkdir -p "$(dirname "$TUNGSTEN_HOME")"
  mv "$tmp/${asset}" "$TUNGSTEN_HOME"
  chmod +x "$TUNGSTEN_HOME/bin/tungsten-compiler" "$TUNGSTEN_HOME/bin/tungsten" 2>/dev/null || true
  rm -rf "$tmp"
  say "installed prebuilt compiler (no bootstrap needed)"
  return 0
}

# --- fall back to cloning + building from source -----------------------------
install_from_source() {
  command -v git >/dev/null 2>&1 || fail "git is required to build from source"
  command -v cc  >/dev/null 2>&1 || fail "a C toolchain is required"
  if [ -d "$TUNGSTEN_HOME/.git" ]; then
    say "updating $TUNGSTEN_HOME"
    git -C "$TUNGSTEN_HOME" pull --ff-only
  else
    say "cloning $TUNGSTEN_REPO -> $TUNGSTEN_HOME"
    git clone --depth 1 "$TUNGSTEN_REPO" "$TUNGSTEN_HOME"
  fi
  say "building the self-hosted compiler (stage 1 = stage 2 byte-identity is checked)"
  "$TUNGSTEN_HOME/bin/tungsten" build
}

# --- install -----------------------------------------------------------------
if [ "${TUNGSTEN_FROM_SOURCE:-0}" = "1" ] || ! install_prebuilt; then
  install_from_source
fi

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
