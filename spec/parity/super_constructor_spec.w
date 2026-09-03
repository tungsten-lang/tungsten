# Classes: calling super from a constructor.
#
# Cross-engine parity spec (scripts/parity.sh).

+ Animal
  ro :name
  -> new(@name)

+ Kitten < Animal
  -> new(name)
    super(name)
    @cute = true
  -> cute?
    @cute

k = Kitten.new("Tom")
<< "super.ctor [k.name] [k.cute?]"
