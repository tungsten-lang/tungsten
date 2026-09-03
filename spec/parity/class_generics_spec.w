## parity xfail type(Box<Integer>.new(1)) is "Box" interpreted but the monomorphized "Box$Integer" compiled (generics are compiled-only in lowering/monomorphize.w)
# Classes: generic classes with a constrained type parameter.
#
# Cross-engine parity spec (scripts/parity.sh).

+ Box<T>
  with T in (Integer Float String)
  -> new(@value)
  -> value
    @value
  -> describe
    "Box([@value])"

b = Box<Integer>.new(1)
<< "generic.int [b.value] [b.describe]"
s = Box<String>.new("hi")
<< "generic.str [s.value]"
<< "generic.type [type(b)]"
