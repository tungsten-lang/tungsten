#!/bin/bash
# Fetch the wasi-libc sysroot + compiler-rt builtins (wasi-sdk release assets)
# into wasm/toolchain/. The C compiler itself is Homebrew LLVM clang (the IR the
# Tungsten compiler emits targets that LLVM, and zig's bundled clang is older).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TC="$ROOT/wasm/toolchain"
VER="${WASI_SDK_VERSION:-34}"
BASE="https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-$VER"
mkdir -p "$TC"
cd "$TC"
if [ ! -d "wasi-sysroot-$VER.0" ]; then
  curl -fL --retry 3 -o sysroot.tgz "$BASE/wasi-sysroot-$VER.0.tar.gz"
  tar xzf sysroot.tgz && rm sysroot.tgz
fi
if [ ! -d "libclang_rt-$VER.0" ]; then
  curl -fL --retry 3 -o rt.tgz "$BASE/libclang_rt-$VER.0.tar.gz"
  tar xzf rt.tgz && rm rt.tgz
fi
ls "$TC"
