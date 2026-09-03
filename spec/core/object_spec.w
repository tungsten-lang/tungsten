# Object — the default root of the class hierarchy (core/object.w).
#
# core/object.w is almost entirely a *declaration* of the protocol every class
# inherits; the bodies come from the runtime. This spec pins the parts that are
# actually dispatched on a plain user class, and records — as BUG notes — the
# declared members that are unimplemented or that the two engines disagree on.
#
# Run:
#   bin/tungsten run --interpret spec/core/object_spec.w
#   bin/tungsten -o /tmp/object_spec spec/core/object_spec.w && /tmp/object_spec

use core/object

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()
  << "PASS " + name

+ Widget
  -> new(@name)

  -> greet
    "hi " + @name

+ Gadget < Widget
  -> greet
    "gadget " + @name

w = Widget.new("a")
g = Gadget.new("b")

# ---- identity and naming ----
check("type names the class", type(w) == "Widget")
check("class returns the class", w.class == Widget)
check("class_name", w.class_name == "Widget")
check("subclass type", type(g) == "Gadget")
check("subclass class_name", g.class_name == "Gadget")

# ---- is_a? walks the ancestry ----
check("is_a? own class", w.is_a?(Widget))
check("is_a? a sibling class is false", !w.is_a?(Gadget))
check("subclass is_a? its own class", g.is_a?(Gadget))
check("subclass is_a? its superclass", g.is_a?(Widget))

# ---- method dispatch and overriding ----
check("instance method", w.greet == "hi a")
check("subclass overrides", g.greet == "gadget b")

# ---- equality ----
check("== is reflexive", w == w)
check("!= is the negation of ==", !(w != w))
check("different classes are not equal", !(w == g))

# ---- hash ----
check("hash is stable", w.hash == w.hash)
check("hash is an integer", type(w.hash) == "Int")

# ---- to_s / interpolation ----
check("to_s is a non-empty string", type(w.to_s) == "String" && w.to_s.size > 0)
check("to_s mentions the class", w.to_s.include?("Widget"))
check("interpolation uses to_s", "[w]" == w.to_s)

# ---- nil? ----
# BUG: with only core/object loaded, `nil.nil?` raises "undefined method 'nil?' for nil"
# compiled (interpreted it is true). Loading core/nil as well makes the compiled engine
# answer correctly, so Object's declared `-> nil? false` shadows the Nil implementation.
# Repro: printf 'use core/object\n<< nil.nil?\n' > /tmp/o.w && bin/tungsten -o /tmp/o /tmp/o.w && /tmp/o
# check("nil is nil", nil.nil?)
# check("a string is not nil", !"x".nil?)

# BUG: `w.is_a?(Object)` is false on both engines even though every class descends
# from Object (Object < BlankSlate), so the ancestry walk stops at the declared class.
# Repro: printf '+ W\n  -> new(@n)\n<< W.new(1).is_a?(Object)\n' > /tmp/o.w && bin/tungsten run --interpret /tmp/o.w
# check("is_a? Object", w.is_a?(Object))
# BUG: Object#respond_to? answers false for a method the class plainly defines (both engines).
# Repro: printf '+ W\n  -> new(@n)\n  -> greet\n    1\n<< W.new(1).respond_to?(:greet)\n' > /tmp/o.w &&
#        bin/tungsten run --interpret /tmp/o.w
# check("respond_to? a defined method", w.respond_to?(:greet))
# check("respond_to? an unknown method is false", !w.respond_to?(:nope))
# BUG: Object#to_s renders "Widget instance" interpreted but "#<Widget>" compiled.
# check("to_s", w.to_s == "#<Widget>")
# BUG: two distinct instances with equal fields compare == interpreted but != compiled.
# Repro: printf '+ W\n  -> new(@n)\n<< (W.new(1) == W.new(1))\n' > /tmp/o.w &&
#        bin/tungsten run --interpret /tmp/o.w   # true;  compiled prints false
# check("structural equality", Widget.new("a") == Widget.new("a"))
# BUG: Object#nil? (declared `-> nil? false`) and Object#freeze raise "undefined method"
# on a plain user instance compiled; interpreted nil? works and freeze returns self.
# check("an object is not nil", !w.nil?)
# check("freeze returns self", w.freeze == w)
# BUG: these declared Object members raise "undefined method" on a plain instance on both
# engines: send, method, tap, try, itself, fields, field_get, field_set, field_defined?,
# frozen?, dup, clone, eql?, instance_of?, kind_of?, to_enum, inspect, mirror, extend,
# include, define_singleton_method, safe, safe?, taint, tainted?, untaint, unsafe, to_b.
# check("send", w.send(:greet) == "hi a")
# check("itself", w.itself == w)
# check("tap yields self and returns self", w.tap(-> (x) x) == w)
# check("try yields self", w.try(-> (x) x.greet) == "hi a")
# check("dup is equal", w.dup == w)
# check("eql? is ==", w.eql?(w))
# check("instance_of? is exact", w.instance_of?(Widget) && !g.instance_of?(Widget))
# check("kind_of? is is_a?", w.kind_of?(Widget))
# check("fields", w.fields.size == 1)
# check("field_get", w.field_get(:name) == "a")
# check("field_defined?", w.field_defined?(:name) && !w.field_defined?(:nope))
# check("inspect", type(w.inspect) == "String")
# BUG: Object#=== (declared `self == @1`) does not parse as a method call —
# "Expected 51, got 151(===)".
# check("=== is ==", w === w)
# BUG: the declared class-level accessors ARGV / ENV / STDIN / STDOUT / STDERR / ARGF are
# not reachable as Object methods on either engine.
# check("ARGV", type(w.ARGV) == "Array")

<< "ALL PASS object_spec ([passed.load()] checks)"
