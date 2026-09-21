# Shared build configuration (sourced by the other scripts).
WASI_SDK_VERSION="${WASI_SDK_VERSION:-34}"
WASM_ROOT="${WASM_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
WASM_LLVM="${WASM_LLVM:-/opt/homebrew/opt/llvm/bin}"
WASM_CLANG="${WASM_CLANG:-$WASM_LLVM/clang}"
WASM_LD="${WASM_LD:-$(command -v wasm-ld || echo /opt/homebrew/opt/lld/bin/wasm-ld)}"
WASM_SYSROOT="$WASM_ROOT/toolchain/wasi-sysroot-$WASI_SDK_VERSION.0"
WASM_RTLIB="$WASM_ROOT/toolchain/libclang_rt-$WASI_SDK_VERSION.0/wasm32-unknown-wasip1/libclang_rt.builtins.a"
WASM_TRIPLE="wasm32-wasip1"
# The ONE place wasm feature flags are chosen. `-mexception-handling` is
# required: raise/rescue is setjmp/longjmp, which wasm lowers onto (legacy)
# exception handling. Everything else stays at LLVM's "generic" baseline so the
# module loads in every current browser and in Cloudflare Workers.
WASM_FEATURE_FLAGS="-mexception-handling"
