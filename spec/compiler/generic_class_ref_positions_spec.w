# spec: compiled -- the interpreter does not bind a template's const-int parameter (Ring<T, N> reading N), elsif or not
# Generic class references must resolve in EVERY syntactic position.
#
# `Name<Args>.new(...)` works only after three walkers have seen the reference:
# the loader's autoload walk for a core template (collect_autoload_refs,
# compiler/lib/loader.w), then the monomorphizer's instantiation collector and
# call-site rewrite (compiler/lib/lowering/monomorphize.w). Each flattened a
# node's child lists only one level deep, so a reference held in a list nested
# inside a child list was never loaded, specialized, or mangled:
#
#   * an elsif arm       — If#elsif_clauses holds [condition, body] pairs
#   * a hash value       — HashLiteral#entries holds [key, value] pairs
#   * an interpolation   — StringInterp#parts holds [tag, expr] pairs
#
# The class then evaluated to nil at runtime ("undefined method 'new' for
# nil"), while the identical expression in an if or else arm worked.
#
# Every instantiation below (template + type arguments) appears in exactly ONE
# position, so no other mention can specialize it first. Do not hoist them.
#
# Run: `bin/tungsten -o /tmp/gcrp spec/compiler/generic_class_ref_positions_spec.w && /tmp/gcrp`

-> check(name, ok)
  if ok
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

+ Box<T>
  ro :v
  -> new(@v)

+ Tagged<T> < Box<T>
  -> doubled
    v * 2

# A const-int parameter read in an elsif arm of the TEMPLATE body must be
# substituted when the template is specialized.
+ Ring<T, N>
  -> .describe(k)
    if k == 0
      "empty"
    elsif k == 1
      N
    else
      "full"

# --- top level: the reported repro (core template, autoloaded) --------------
mode = "b"
top = 0
if mode == "a"
  top = -1
elsif mode == "b"
  top = Quaternion<f64>.new([~1.0, ~2.0, ~3.0, ~4.0] ## f64[4]).w.to_i
check("toplevel.elsif.core_template", top == 1)

# --- top level: user template in each arm of one chain ----------------------
arm = "second"
picked = 0
if arm == "first"
  picked = Box<Integer>.new(1).v
elsif arm == "never"
  picked = Box<String>.new(2).v
elsif arm == "second"
  picked = Box<Float>.new(3).v
else
  picked = Box<Symbol>.new(4).v
check("toplevel.elsif.second_arm", picked == 3)

# The condition of an elsif is inside the same [condition, body] pair.
cond_hit = 0
if arm == "first"
  cond_hit = -1
elsif Box<Bool>.new(7).v == 7
  cond_hit = 7
check("toplevel.elsif.condition", cond_hit == 7)

# A generic subclass of a generic parent, named only in an elsif arm.
sub = 0
if arm == "first"
  sub = -1
elsif arm == "second"
  sub = Tagged<Char>.new(5).doubled
check("toplevel.elsif.generic_subclass", sub == 10)

# Nested: an elsif inside an elsif arm.
deep = 0
if arm == "first"
  deep = -1
elsif arm == "second"
  if arm == "x"
    deep = -2
  elsif arm == "second"
    deep = Box<Range>.new(11).v
check("toplevel.elsif.nested", deep == 11)

# --- inside a method ---------------------------------------------------------
-> choose(which)
  if which == 1
    Box<Hash>.new(10).v
  elsif which == 2
    Box<Array>.new(20).v
  elsif which == 3
    Quaternion<f32>.new([~5.0, ~6.0, ~7.0, ~8.0] ## f32[4]).w.to_i
  else
    Box<Decimal>.new(40).v

check("method.if_arm", choose(1) == 10)
check("method.elsif_arm", choose(2) == 20)
check("method.elsif_core_template", choose(3) == 5)
check("method.else_arm", choose(4) == 40)

# --- other nested child lists -----------------------------------------------
h = {"k": Box<Rational>.new(30).v}
check("hash_literal.value", h["k"] == 30)

text = "got [Box<Duration>.new(31).v]"
check("string_interp.part", text == "got 31")

# --- template bodies and SmallArray sugar in elsif arms ---------------------
check("template_body.elsif_const_int", Ring<i32, 8>.describe(1) == 8)

-> small_len(k)
  if k == 0
    0
  elsif k == 1
    SmallArray<i64, 6>.new.size
  else
    -1
check("elsif.smallarray_ctor", small_len(1) == 6)

<< "generic_class_ref_positions_spec: all checks passed"
