# Host-parity spec for typed-overload selection (B1 / verification 7).
#
# The same source must select the same arms on every host that executes
# Tungsten during bootstrap or development:
#   bin/tungsten -o /tmp/t spec/compiler/typed_overload_hosts_spec.w && /tmp/t
#   bin/tungsten spec/compiler/typed_overload_hosts_spec.w
#   bin/tungsten --ruby spec/compiler/typed_overload_hosts_spec.w
#   implementations/c/build/tungsten-c spec/compiler/typed_overload_hosts_spec.w
#
# "BigInt" matches by the exact-tag rule (an integer beyond the inline
# i48 payload — the C VM mirrors this with its heap-int test); "Number"
# is the ancestry catch-all. `order` declares the Number arm FIRST so a
# host that honors declaration order over specificity fails loudly.
# `relay` exercises the implicit-self (bare sibling call) dispatch route,
# which historically bypassed typed selection on more than one host.
# The `-> new` returning nil is the stage-0 C VM's initializer
# convention; the other hosts construct through their own protocols and
# treat it as inert.

+ HostBox
  -> new
    nil

  -> combine(other)(BigInt)
    "bigint-arm"

  -> combine(other)(Number)
    "number-arm"

  -> pick/1(BigInt)
    "big"

  -> pick/1(Number)
    "num"

  -> order(other)(Number)
    "general-first"

  -> order(other)(BigInt)
    "specific-wins"

  -> relay(x)
    pick(x)

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()

host = HostBox.new
small = 5
big = 1 << 50

check("named.small", host.combine(small), "number-arm")
check("named.big", host.combine(big), "bigint-arm")
check("arity.small", host.pick(small), "num")
check("arity.big", host.pick(big), "big")
check("relay.small", host.relay(small), "num")
check("relay.big", host.relay(big), "big")
check("relay.small2", host.relay(small), "num")
check("order.small", host.order(small), "general-first")
check("order.big", host.order(big), "specific-wins")
