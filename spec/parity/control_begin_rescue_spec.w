# Control flow: begin/rescue as a value, ensure, postfix rescue, raised
# strings, error objects and their messages, nested rescue.
#
# Cross-engine parity spec (scripts/parity.sh).

-> boom
  raise "kaboom"

-> r_value
  begin
    boom()
    1
  rescue e
    42

<< "begin.value [r_value()]"
v = begin
  boom()
  10
rescue e
  20
<< "begin.assign [v + 1]"
-> r_ensure(log)
  begin
    boom()
    "body"
  rescue e
    "rescued"
  ensure
    log.push("ensured")
log = []
<< "ensure.value [r_ensure(log)] [log.join(",")]"
ok = 7 rescue "nope"
<< "postfix.ok [ok]"
caught = (boom() rescue "caught")
<< "postfix.caught [caught]"
a = begin
  boom()
rescue e
  "[type(e)]|[e]"
<< "raise.str [a]"
-> boom_obj
  raise Error.new("boom")
b = begin
  boom_obj()
rescue e
  "[type(e)]|[e.message]|[e]"
<< "raise.obj [b]"
-> boom_arg
  raise ArgumentError, "bad arg"
c = begin
  boom_arg()
rescue e
  "[type(e)]|[e.message]|[e.class]"
<< "raise.arg [c]"
d = begin
  "5" + 3
rescue e
  "[type(e)]|[e]"
<< "type.error [d]"
nested = begin
  begin
    boom()
  rescue e
    raise "outer"
rescue e2
  "[e2]"
<< "nested [nested]"
noerr = begin
  5
rescue e
  6
<< "noerr [noerr]"
