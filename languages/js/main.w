# runtime/main — the JS runtime, in load order. A compiled program declares
# `JS_IC = i64[8 + 4 × sites]` before it `use`s this file, and defines js_dispatch
# (tools/jsc.w generates both).

use prims
use gc_core
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
use rx_unicode
use regexp
use b_collections
use b_promise
use b_dispose
use b_shadowrealm
use b_icu
use b_intl
use b_intl_fmt
use b_temporal_core
use b_temporal_cal
use b_temporal
use b_temporal_zdt
use coro
