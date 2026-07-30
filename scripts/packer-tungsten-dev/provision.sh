#!/usr/bin/env bash
# Provision a Tungsten dev image (runs on both arm64 and x86_64 — every tool
# here is either arch-portable via dnf/pip/gem or built from source).
set -euxo pipefail

ARCH="$(uname -m)"
echo "=== provisioning tungsten-dev for ${ARCH} ==="

dnf -y update
dnf -y groupinstall "Development Tools" || true

# --- Tungsten build toolchain -------------------------------------------------
# clang/llvm/lld: the WIRE->LLVM->native backend. gcc/make/cmake: C VM + runtime.
# libzstd/openblas headers are required by the current bootstrap/runtime bridge.
dnf -y install \
  git make cmake ninja-build pkgconf \
  gcc gcc-c++ clang clang-tools-extra llvm llvm-devel lld \
  zlib-devel libzstd-devel openblas-devel \
  openssl-devel libffi-devel libxml2-devel ncurses-devel readline-devel \
  jq tmux htop
# curl is deliberately absent: AL2023 ships curl-minimal (which provides
# /usr/bin/curl), and installing full curl conflicts with it, aborting the
# image build under `set -euxo pipefail`.

# --- Ruby (the --ruby bootstrap interpreter + the gem) ------------------------
dnf -y install ruby ruby-devel rubygems
gem install --no-document bundler rake rspec rubocop

# --- Python + the scikit-learn ML stack ---------------------------------------
dnf -y install python3 python3-pip python3-devel
python3 -m pip install --upgrade pip wheel setuptools
# scikit-learn stack (arm64 + x86_64 manylinux wheels both exist)
python3 -m pip install numpy scipy scikit-learn pandas matplotlib joblib
# Verify wheels installed as binaries (not slow source builds) on this arch:
python3 -c "import numpy,scipy,sklearn,pandas; print('py-ml ok:', numpy.__version__, sklearn.__version__)"
# Heavier CPU ML frameworks — uncomment as needed (large; on x86 prefer the
# CUDA build on a GPU box instead of baking it here):
# python3 -m pip install torch --index-url https://download.pytorch.org/whl/cpu

# --- SAT solvers (built from source → correct on both arches) -----------------
build_sat() { # $1 repo  $2 binary-name-in-build-dir
  local dir="/opt/$(basename "$1")"
  git clone --depth 1 "https://github.com/arminbiere/$1.git" "$dir"
  ( cd "$dir" && ./configure && make -j"$(nproc)" && install -m0755 "build/$2" /usr/local/bin/ )
}
build_sat cadical cadical
build_sat kissat  kissat
cadical --version && kissat --version

# --- sanity: full native toolchain present ------------------------------------
clang --version | head -1
printf '#include <zstd.h>\n#include <cblas.h>\nint main(void) { return 0; }\n' \
  | clang -fuse-ld=lld -x c - -o /tmp/tungsten-toolchain-smoke
/tmp/tungsten-toolchain-smoke
rm -f /tmp/tungsten-toolchain-smoke
cc --version | head -1
ruby --version
python3 --version

echo "=== tungsten-dev provisioning complete (${ARCH}) ==="
