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
use proto
use support
use arguments
use helpers
use b_object
use b_iter
use b_array
use b_string
use b_number
use b_json
use b_console
use b_reflect
use b_date
use b_typed
use regexp
use b_collections
use b_promise
use coro
