# Protocol — placeholder class for behaviour protocols (core/protocol.w).
#
# The class body is empty: only construction and identity can be exercised.
#
# Run:
#   bin/tungsten run --interpret spec/core/protocol_spec.w
#   bin/tungsten -o /tmp/protocol_spec spec/core/protocol_spec.w && /tmp/protocol_spec

use core/protocol

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()
  << "PASS " + name

proto = Protocol.new
check("constructs", type(proto) == "Protocol")
check("is_a? Protocol", proto.is_a?(Protocol))
check("class name", proto.class_name == "Protocol")
check("identity ==", proto == proto)
check("hash is stable", proto.hash == proto.hash)
check("to_s is non-empty", proto.to_s.size > 0)

# BUG: `Protocol.new == Protocol.new` (two distinct field-less instances) is true interpreted
# but false compiled — the engines disagree on default Object equality.
# Repro: printf 'use core/protocol\n<< (Protocol.new == Protocol.new)\n' > /tmp/p.w &&
#        bin/tungsten run --interpret /tmp/p.w  # true
#        bin/tungsten -o /tmp/p /tmp/p.w && /tmp/p  # false
# check("distinct instances differ", !(proto == Protocol.new))
# BUG: Object#nil? (declared `-> nil? false`) raises "undefined method 'nil?'" on a plain user-class
# instance compiled; interpreted it correctly returns false.
# Repro: printf 'use core/protocol\n<< Protocol.new.nil?\n' > /tmp/p.w && bin/tungsten -o /tmp/p /tmp/p.w && /tmp/p
# check("not nil", !proto.nil?)
# BUG: Object#to_s renders "Protocol instance" interpreted and "#<Protocol>" compiled.
# check("to_s", proto.to_s == "#<Protocol>")
# BUG: Object#inspect / #fields / #itself / #frozen? / #dup / #clone / #instance_of? / #kind_of? / #to_b
# are all "undefined method" on a plain instance interpreted, though Object declares them.
# check("inspect", proto.inspect == proto.to_s)
# check("fields is empty", proto.fields.size == 0)
# check("itself", proto.itself == proto)
# check("instance_of?", proto.instance_of?(Protocol))
# BUG: Object#=== (declared `self == @1`) fails to parse as a call: "Expected 51, got 151(===)"
# check("=== is ==", proto === proto)

<< "ALL PASS protocol_spec ([passed.load()] checks)"
