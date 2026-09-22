# super in a value-returning method calls the superclass method of the
# same name and returns its value.
#
# Cross-engine parity spec (scripts/parity.sh).

+ Parent
  -> greet
    "hello"

+ Child < Parent
  -> greet
    super + "!"

<< Child.new.greet
