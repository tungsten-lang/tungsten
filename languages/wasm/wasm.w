# wasm — the WebAssembly engine: load order of every piece.
#
#   m = wasm_decode(bytes)              # binary → WModule (raises WasmMalformed)
#   wasm_validate(m)                    # validate and compile to interpreter code (WasmInvalid)
#   inst = wasm_instantiate(store, m, imports)
#
# See README.md for the design.

use types
use reader
use opcodes
use wat
use ops
use kernels
use compile
use simd
use validate
use interp
use simd_exec
use runtime
use gc
use atomic
