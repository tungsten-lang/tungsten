# runtime/coro — generators, async functions and async generators on goroutines.
#
# Tier 0 runs the body of each generator or async call on a goroutine and talks to it
# over two unbuffered channels (ported from Blade's engine, blade/js/runtime.w). The
# body is a Tungsten lambda that runs the function to completion; inside it, yield and
# await hand a message out and wait to be resumed. Milestone 4 replaces this with
# resumable functions (a Coroutine state machine), first for compiled code.
#
# Messages out: [:yield, v] [:yield_raw, iterResult] [:await, v] [:return, v] [:throw, v]
# [:call, coro, msg, first] (a coroutine asking the main stack to resume another one).
# Messages in: [:next, v] [:throw, v] [:return, v].

in JS

+ Coro
  rw :to, :from, :state, :body
  -> new(@body)
    @to = nil
    @from = nil
    @state = :start

# Raised inside a generator body to run its finally blocks and return (gen.return()).
+ GenReturn < Error
  ro :value
  -> new(@value)
    nil

+ Generator < JS:Special
  rw :coro
  -> new(@shape)
    @cls = "Generator"
    @ext = nil
    @internal = nil
    @s0 = nil
    @s1 = nil
    @s2 = nil
    @s3 = nil
    @coro = nil
    jsr_set_kind(wvalue_bits(self) ## i64, KIND_OBJECT)

+ AsyncGen < JS:Special
  rw :coro, :queue, :busy
  -> new(@shape)
    @cls = "AsyncGenerator"
    @ext = nil
    @internal = nil
    @s0 = nil
    @s1 = nil
    @s2 = nil
    @s3 = nil
    @coro = nil
    @queue = []
    @busy = false
    jsr_set_kind(wvalue_bits(self) ## i64, KIND_OBJECT)

# The coroutine whose body is running on this thread (nil on the main stack).
JS_CUR_CORO = [nil]
JS_CORO_LIVE = [0]
JS_GOROUTINE_INIT = [false]

-> js_coro_spawn(c)
  if !JS_GOROUTINE_INIT[0]
    JS_GOROUTINE_INIT[0] = true
    n = (4194304 ## int)
    ccall("w_goroutine_stack_size_hint", n)
  JS_CORO_LIVE[0] += 1
  if JS_CORO_LIVE[0] > 9000
    JS_CORO_LIVE[0] -= 1
    js_throw_range("Too many suspended generators and async functions")
  c.to = Channel.new(0)
  c.from = Channel.new(0)
  go ->
    js_coro_body(c)
  nil

# Only the main stack hands control to a coroutine (two goroutines rendezvousing on
# unbuffered channels while main waits deadlocks the scheduler): a coroutine that wants
# to resume another asks main to with :call.
-> js_coro_resume(c, msg, first)
  cur = JS_CUR_CORO[0]
  return js_coro_drive(c, msg, first) if cur == nil
  cur.from.send([:call, c, msg, first])
  reply = cur.to.receive
  reply[1]

-> js_coro_drive(c, msg, first)
  JS_CUR_CORO[0] = c
  if first
    js_coro_spawn(c)
  else
    c.to.send(msg)
  js_coro_wait(c)

-> js_coro_wait(c)
  while true
    m = c.from.receive
    JS_CUR_CORO[0] = nil
    if m[0] == :call
      res = js_coro_drive(m[1], m[2], m[3])
      JS_CUR_CORO[0] = c
      c.to.send([:ret, res])
    else
      return m
  nil

-> js_coro_body(c)
  msg = nil
  begin
    v = c.body.call()
    msg = [:return, v]
  rescue e
    if e.is_a?(JS:GenReturn)
      msg = [:return, e.value]
    else
      msg = [:throw, js_error_value(e)]
  JS_CORO_LIVE[0] -= 1
  c.from.send(msg)
  nil

# ---- generators ----

-> js_gen_create(f, body)
  p = jget(f, "prototype")
  p = js_realm().intrinsic("%GeneratorPrototype%") if !js_object?(p)
  g = JS:Generator.new(js_root_shape(p, SP_INLINE, SP_IBASE))
  g.coro = JS:Coro.new(body)
  g

-> js_req_gen(g)
  js_throw_type("next method called on incompatible receiver " + js_to_display_short(g)) if !g.is_a?(JS:Generator)
  g

# Resume a generator: kind is :next, :throw or :return. Returns the iterator result.
-> js_gen_resume(g, kind, v)
  c = g.coro
  st = c.state
  js_throw_type("Generator is already running") if st == :running
  if st == :done
    js_throw(v) if kind == :throw
    return js_iter_result(kind == :return ? v : nil, true)
  msg = nil
  if st == :start
    if kind == :return
      c.state = :done
      return js_iter_result(v, true)
    if kind == :throw
      c.state = :done
      js_throw(v)
    c.state = :running
    msg = js_coro_resume(c, nil, true)
  else
    c.state = :running
    msg = js_coro_resume(c, [kind, v], false)
  k = msg[0]
  if k == :yield
    c.state = :suspended
    return js_iter_result(msg[1], false)
  if k == :yield_raw
    c.state = :suspended
    return msg[1]
  c.state = :done
  c.body = nil
  js_throw(msg[1]) if k == :throw
  js_iter_result(msg[1], true)

# Inside a generator's goroutine: hand v out and wait to be resumed.
-> js_yield(c, v)
  c.from.send([:yield, v])
  js_after_suspend(c.to.receive)

# What a resumed generator does with the message it was resumed with.
-> js_after_suspend(msg)
  k = msg[0]
  return msg[1] if k == :next
  js_throw(msg[1]) if k == :throw
  raise JS:GenReturn.new(msg[1])

# yield* iterable (§15.5.5).
-> js_yield_star(c, iterable)
  rec = js_get_iterator(iterable)
  received_kind = :next
  received = nil
  while true
    r = nil
    if received_kind == :next
      r = js_call_arr(rec.next_fn, rec.iterator, [received])
    elsif received_kind == :throw
      th = js_get_method(rec.iterator, "throw")
      if th == nil
        js_iter_close(rec)
        js_throw_type("The iterator does not provide a 'throw' method")
      r = js_call_arr(th, rec.iterator, [received])
    else
      rt = js_get_method(rec.iterator, "return")
      raise JS:GenReturn.new(received) if rt == nil
      r = js_call_arr(rt, rec.iterator, [received])
      js_throw_type("iterator result is not an object") if !js_object?(r)
      raise JS:GenReturn.new(jget(r, "value")) if js_truthy(jget(r, "done"))
    js_throw_type("iterator result is not an object") if !js_object?(r)
    return jget(r, "value") if js_truthy(jget(r, "done")) && received_kind != :return
    c.from.send([:yield_raw, r])
    msg = c.to.receive
    received_kind = msg[0]
    received = msg[1]
  nil

# ---- async functions ----

-> js_async_start(body)
  js_async_start_coro(JS:Coro.new(body))

-> js_async_start_coro(c)
  cap = js_new_capability()
  c.state = :running
  js_async_step(c, cap, js_coro_resume(c, nil, true))
  cap.promise

-> js_async_step(c, cap, msg)
  k = msg[0]
  if k == :await
    c.state = :suspended
    js_promise_then_native(msg[1], ->(x) js_async_resume(c, cap, :next, x), ->(x) js_async_resume(c, cap, :throw, x), [c, cap])
    return nil
  c.state = :done
  c.body = nil
  if k == :return
    js_call_arr(cap.resolve, nil, [msg[1]])
  else
    js_call_arr(cap.reject, nil, [msg[1]])
  nil

-> js_async_resume(c, cap, kind, v)
  c.state = :running
  js_async_step(c, cap, js_coro_resume(c, [kind, v], false))
  nil

# Inside an async body's goroutine.
-> js_await(c, v)
  c.from.send([:await, v])
  msg = c.to.receive
  return msg[1] if msg[0] == :next
  js_throw(msg[1])

# ---- async generators ----

-> js_async_gen_create(f, body)
  p = jget(f, "prototype")
  p = js_realm().intrinsic("%AsyncGeneratorPrototype%") if !js_object?(p)
  g = JS:AsyncGen.new(js_root_shape(p, SP_INLINE, SP_IBASE))
  g.coro = JS:Coro.new(body)
  g

# next/throw/return on an async generator: queue the request, return its promise.
-> js_async_gen_enqueue(g, kind, v)
  cap = js_new_capability()
  if !g.is_a?(JS:AsyncGen)
    js_call_arr(cap.reject, nil, [js_make_error("TypeError", "not an async generator")])
    return cap.promise
  g.queue.push([kind, v, cap])
  js_async_gen_drain(g) if !g.busy
  cap.promise

-> js_async_gen_drain(g)
  c = g.coro
  while g.queue.size > 0 && !g.busy
    req = g.queue[0]
    kind = req[0]
    v = req[1]
    if c.state == :done || (c.state == :start && kind != :next)
      g.queue.shift
      c.state = :done
      if kind == :throw
        js_call_arr(req[2].reject, nil, [v])
      else
        js_call_arr(req[2].resolve, nil, [js_iter_result(kind == :return ? v : nil, true)])
    else
      g.busy = true
      first = c.state == :start
      c.state = :running
      js_async_gen_step(g, js_coro_resume(c, first ? nil : [kind, v], first))
  nil

-> js_async_gen_step(g, msg)
  c = g.coro
  k = msg[0]
  if k == :await
    js_promise_then_native(msg[1], ->(x) js_async_gen_resume(g, :next, x), ->(x) js_async_gen_resume(g, :throw, x), [g])
    return nil
  req = g.queue.shift
  g.busy = false
  if k == :yield
    c.state = :suspended
    js_call_arr(req[2].resolve, nil, [js_iter_result(msg[1], false)])
  elsif k == :return
    c.state = :done
    js_call_arr(req[2].resolve, nil, [js_iter_result(msg[1], true)])
  else
    c.state = :done
    js_call_arr(req[2].reject, nil, [msg[1]])
  js_async_gen_drain(g)
  nil

-> js_async_gen_resume(g, kind, v)
  js_async_gen_step(g, js_coro_resume(g.coro, [kind, v], false))
  nil

# yield inside an async generator: await the value, then hand it out.
-> js_async_yield(c, v)
  v = js_await(c, v)
  c.from.send([:yield, v])
  msg = c.to.receive
  k = msg[0]
  return msg[1] if k == :next
  js_throw(msg[1]) if k == :throw
  raise JS:GenReturn.new(js_await(c, msg[1]))
