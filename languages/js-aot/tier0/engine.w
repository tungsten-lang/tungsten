# blade/js/engine — the JavaScript engine: load order of every piece.
#
#   realm = js_new_realm(host)      # a JsHost subclass, or nil for stdout
#   js_run_script(src)              # compile and run a classic script
#   realm.run_jobs                  # drain microtasks
#
# Tiers: interp.w compiles each function to closures on its first call (lazy parsing skips
# bodies until then); aot.w compiles hot functions to native code in the background and
# caches it per script content (~/Library/Caches/Blade/jsaot/).
#
# The lexer and parser are copies of languages/javascript/ on the Tungsten js-frontend
# branch (Blade takes no shared code); value.w, realm.w and the rest mirror the js-runtime
# branch's languages/javascript/runtime/.

use tls
use ../frontend/lexer
use ../frontend/parser
use value
use realm
use ops
use runtime
use interp
use b_object
use b_array
use b_iter
use b_string
use b_number
use b_json
use b_promise
use b_collections
use b_console
use regexp
use b_date
use b_reflect
use b_typed
use module
use aot
use gc

-> js_new_realm(host)
  r = JsRealm.new
  r.host = host
  js_gc_add_realm(r) if js_gc_main_thread?
  r

# installers registered so far are the engine's own (trusted by the collector)
JS_GC_ENGINE_INSTALLERS = [JS_INSTALLERS.size]
