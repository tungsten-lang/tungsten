# A top-level binding must not retroactively capture an unqualified zero-arg
# method read inside a class body. The compiler predeclares module globals so
# methods may refer to bindings initialized later, but method lookup remains
# lexical to the receiver when that method is known.

+ HygieneBase
  -> marker
    "method"

+ HygieneChild < HygieneBase
  -> inherited_marker
    marker

+ HygieneDirect
  -> zero
    0

  -> zero?(value)
    value == zero

raise "direct method was captured by top-level binding" if !HygieneDirect.new.zero?(0)
raise "inherited method was captured by top-level binding" if HygieneChild.new.inherited_marker != "method"

# These assignments deliberately follow the calls. The interpreter has not
# introduced them when the methods run; the compiler's declaration prepass
# must not make them visible retroactively.
marker = "global"
zero = "global"

# Once the module bindings exist at runtime, both direct and inherited method
# reads must still remain lexical to self in the interpreter as well.
raise "direct method was captured by initialized top-level binding" if !HygieneDirect.new.zero?(0)
raise "inherited method was captured by initialized top-level binding" if HygieneChild.new.inherited_marker != "method"

<< "top_level_method_name_hygiene_spec: all checks passed"
