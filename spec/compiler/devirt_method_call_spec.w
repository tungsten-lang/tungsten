# Guarded method-call devirtualization (lowering/method_call.w devirt_fn →
# emitter :call_method_i64 dv.* arms). A local assigned `C.new(...)` gets an
# exact-class fact; calls on it emit a class-id-guarded DIRECT call with the
# IC dispatch as the fallback arm. The guard (instance subtag + class_id
# equality against @class.C) is the soundness backstop: subclass instances,
# reassigned locals, and stale facts must all fail the guard and dispatch
# through the IC exactly as before.
#
# Run: `bin/tungsten -o /tmp/dvs spec/compiler/devirt_method_call_spec.w && /tmp/dvs`

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

+ Animal
  -> new(@name)
    self
  -> speak
    "generic"
  -> tag(n)
    n + 1

+ Dog < Animal
  -> new(@name)
    self
  -> speak
    "woof"
  -> tag(n)
    n + 100

# devirtualized: exact class, monomorphic
a = Animal.new("a")
check("devirt.exact_speak", a.speak, "generic")
check("devirt.exact_tag", a.tag(5), 6)

# reassignment to a SUBCLASS: the class-id guard must fail and the IC
# must dispatch Dog's overrides
a = Dog.new("d")
check("devirt.reassigned_subclass_speak", a.speak, "woof")
check("devirt.reassigned_subclass_tag", a.tag(5), 105)

# conditional reassignment: the static fact is stale on one path; the
# guard decides at runtime
c = Animal.new("c")
flag = 1 ## i64
if flag > 0
  c = Dog.new("cc")
check("devirt.stale_fact_guarded", c.speak, "woof")

# devirtualized call in a hot loop (accumulates through the direct arm)
b = Animal.new("b")
r = 0 ## i64
j = 0 ## i64
while j < 100
  r = r + b.tag(j)
  j = j + 1
check("devirt.loop_accumulate", r, 5050)

# ivar-receiver devirt (exact_source_ivar_types path)
+ Holder
  -> new
    @pet = Animal.new("h")
    self
  -> ask
    @pet.speak

h = Holder.new
check("devirt.ivar_receiver", h.ask, "generic")

# methods with defaults/blocks are NOT devirtualized (map excludes them) —
# behavior must remain correct through the IC path
+ Deft
  -> new
    self
  -> add(x, y = 10)
    x + y

d = Deft.new
check("devirt.default_param_excluded", d.add(1), 11)
check("devirt.default_param_both", d.add(1, 2), 3)

# `class.new` can allocate and invoke a plain initializer directly only when
# the runtime class is exactly the method's owner. Inherited calls on a
# subclass must take the constructor IC fallback and preserve that subclass.
+ FactoryBase
  -> new(@label)
    self
  -> duplicate
    class.new(@label)
  -> kind
    "base"

+ FactoryChild < FactoryBase
  -> new(@label)
    self
  -> kind
    "child"

fb = FactoryBase.new("b")
check("construct.exact_class", fb.duplicate.kind, "base")
fc = FactoryChild.new("c")
check("construct.subclass_fallback", fc.duplicate.kind, "child")

# A static `.new` shadows allocate-then-initialize dispatch. Its presence must
# disable guarded constructor lowering even when an instance initializer with
# the same source name also exists.
+ StaticNewShadow
  -> new(@value)
    self
  -> .new(value)
    "static " + value
  -> .build(value)
    class.new(value)

check("construct.static_new_shadow", StaticNewShadow.build("ok"), "static ok")
check("construct.static_new_shadow_cached", StaticNewShadow.build("again"), "static again")

# The static factory can be inherited even when the subclass declares its own
# instance initializer. Scan the whole hierarchy before selecting a direct
# constructor worker.
+ InheritedStaticNew
  -> .new(value)
    "inherited " + value

+ InheritedStaticNewChild < InheritedStaticNew
  -> new(@value)
    self
  -> .build(value)
    class.new(value)

check("construct.inherited_static_new", InheritedStaticNewChild.build("ok"), "inherited ok")
