# return-through-ensure: `return expr` inside begin/ensure must (1) evaluate
# expr FIRST, (2) then run the ensure body, (3) then return the already-
# computed value — an ensure that reassigns the returned local must not
# change the returned value. Spec 4.6.5. Compiled lowering used to branch
# straight to the function exit, skipping the ensure body entirely.
#
# (ivars are seeded in the method under test, not `initialize` — interpreted
# `.new` does not run initialize; pre-existing interp gap, out of scope here)
+ Probe
  -> compute(v)
    @journal = @journal + "C"
    v + 10

  -> run
    @journal = ""
    begin
      return compute(1)
    ensure
      @journal = @journal + "E"

  -> run2
    v = 1
    begin
      return v
    ensure
      v = 99

  -> journal
    @journal

p = Probe.new
<< "result:" + p.run().to_s()
<< "order:" + p.journal()
<< "result2:" + p.run2().to_s()
