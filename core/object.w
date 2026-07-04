# # Object
#
# Object is the default root of all Tungsten objects. Object inherits from BlankSlate (the
# explicit blank root) which allows creating alternate object hierarchies. Methods on Object
# are available to all classes unless explicitly overridden.
#
# The Global module's functions (core/global.w) are made globally accessible by
# the runtime, so they are callable from every object without being mixed in
# here as a trait — `is Global` would name a module, not a trait.
#
# When referencing constants in classes inheriting from Object you do not need to use
# the full namespace. For example, referencing `File` inside `YourClass` will find the top-level
# `File` class.
+ Object < BlankSlate
  -> ARGF
  -> ARGV
  -> ENV
  -> STDERR
  -> STDIN
  -> STDOUT

  -> allocate
  -> initialize
  -> new

  # Equality
  -> ==/1
  -> !=/1
    !(self == @1)

  # Case Equality
  -> ===/1
    self == @1

  -> <=>/1

  -> !~/1
    !(self =~ @1)

  -> =~/1 nil

  -> >/1
  -> >=/1
  -> </1
  -> <=/1

  -> []/1
  -> []=/2

  -> to_b/0

  -> class
  -> class_name
  -> clone

  -> define_singleton_method(name, method)
  -> define_singleton_method(name, &)
  -> dup

  -> eql?/1

  -> extend/1

  -> field_defined?/1:string
  -> field_defined?/1:symbol
  -> field_get/1
  -> field_set/2
  -> fields
  -> freeze
  -> frozen?

  -> hash/0
  -> type

  -> include/1
  -> inspect/0
  -> instance_of?/1:class
  -> is_a?/1:class

  -> kind_of?/1:class

  -> method/1

  -> mirror
    "[class_name]Mirror".constantize.new(self)

  -> nil? false

  -> itself
    self

  -> respond_to?/1

  # Bodyless — the runtime supplies it (w_method_dispatch). True when the
  # receiver is an instance of the given class or any of its ancestors.
  -> is_a?/1

  # @todo pick safe or taint terminology
  -> safe
  -> safe?

  -> send(name, *args)

  -> taint
  -> tainted?
  -> try(&)
    yield self

  # Yields _self_ to the block, and then returns _self_.
  -> tap(&)
    yield self
    self

  -> to_enum(method = :each, *args)
  -> to_enum(method = :each, *args, &)

  -> to_s
    if fields.any?
      "#<[class] [fields.debug]>"
    else
      "#<[class]>"

  -> untaint
  -> unsafe
