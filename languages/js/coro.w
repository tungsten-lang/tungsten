# runtime/coro — Generator and AsyncGenerator object shells backed by stackless SmFrame (sm_coro.w).
#
# Completely eliminates goroutines, channels, and the 9,000 live-generator cap!

in JS

# Kept for blade/jsdom js_shutdown compat (always 0: stackless state machines use zero goroutines).
JS_CORO_LIVE = [0]

# Raised inside a generator when needed for compat.
+ GenReturn < Error
  ro :value
  -> new(@value)
    nil

+ Generator < JS:Special
  rw :frame
  -> new(@shape)
    @cls = "Generator"
    @ext = nil
    @internal = nil
    @s0 = nil
    @s1 = nil
    @s2 = nil
    @s3 = nil
    @frame = nil
    jsr_set_kind(wvalue_bits(self) ## i64, KIND_OBJECT)

+ AsyncGen < JS:Special
  rw :frame, :queue, :busy
  -> new(@shape)
    @cls = "AsyncGenerator"
    @ext = nil
    @internal = nil
    @s0 = nil
    @s1 = nil
    @s2 = nil
    @s3 = nil
    @frame = nil
    @queue = []
    @busy = false
    jsr_set_kind(wvalue_bits(self) ## i64, KIND_OBJECT)

-> js_req_gen(g)
  js_throw_type("next method called on incompatible receiver " + js_to_display_short(g)) if !g.is_a?(JS:Generator)
  g

-> js_gen_resume(g, kind, v)
  js_sm_gen_resume(g, kind, v)

-> js_async_gen_enqueue(g, kind, v)
  js_sm_async_gen_enqueue(g, kind, v)
