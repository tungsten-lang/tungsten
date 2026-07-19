# Repro: a `go` body must capture the enclosing method's LOCALS as reliably
# as its PARAMS, and both must survive the frame returning before the
# goroutine runs. Historically params worked but a local still living in
# ctx[:bindings] was invisible to capture discovery (lower_go skipped
# materialize_bindings), so `tag` lowered as a bogus implicit-self call.
# Compiled-only: Channel / goroutines are compiled-runtime builtins.
# (Cooperative scheduler: goroutines run inside the blocking recv, well
# after both frames below have returned.)

+ Spawner
  -> run_param(tag, ch)
    go ->
      ch.send("param:" + tag)

  -> run_local(ch)
    tag = "loc" + "al"
    go ->
      ch.send("local:" + tag)

ch = Channel.new(4)
s = Spawner.new
s.run_param("pval", ch)
s.run_local(ch)
a = ch.recv()
b = ch.recv()
res = [a, b]
<< "param ok: " + res.include?("param:pval").to_s()
<< "local ok: " + res.include?("local:local").to_s()
