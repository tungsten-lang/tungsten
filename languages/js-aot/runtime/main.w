# runtime/main — the JS runtime, in load order. A compiled program declares
# `JS_IC = i64[8 + 4 × sites]` before it `use`s this file, and defines js_dispatch
# (tools/jsc.w generates both).

use prims
use value
use object
use function
use array
use realm
use ops
use support
