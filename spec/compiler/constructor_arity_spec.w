# Constructor protocol: `.new` with arguments requires a constructor.
#
# `-> new(...)` IS Tungsten's constructor (spec 5.3.1). `init` and
# `initialize` are ordinary methods that `.new` never calls, and neither
# `ro :field` nor a `- data` block generates a constructor. Passing
# arguments with no constructor to receive them used to be silently
# dropped: `.new` returned an object with every field unset, so the
# mistake surfaced far away as a nil field read. It now raises, naming
# the required form.
#
# Checked in both engines — the runtime (w_method_dispatch `new` arm)
# serves compiled code, and interpreter.w#instantiate serves --ruby-less
# interpretation; they must agree.
#
# Run: `bin/tungsten -o /tmp/cas spec/compiler/constructor_arity_spec.w && /tmp/cas`

-> check(name, got, want)
  if got.to_s() == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want
    exit 1

# --- the constructor works, including @-parameter field binding ---
+ Holder
  -> new(@label)
    self
  -> label
    @label
check("ctor.binds_field", Holder.new("hello").label, "hello")

+ Pair
  -> new(@a, @b)
    self
  -> sum
    @a + @b
check("ctor.two_fields", Pair.new(2, 3).sum, "5")

# Constructors are inherited through the superclass chain.
+ Base
  -> new(@v)
    self
  -> v
    @v
+ Derived < Base
check("ctor.inherited", Derived.new("inherited").v, "inherited")

# --- no constructor + no arguments stays legal ---
+ Plain
  -> greet
    "hi"
check("ctor.zero_args_ok", Plain.new.greet, "hi")

+ WithField
  ro :name
  -> unset?
    @name == nil
check("ctor.ro_zero_args_ok", WithField.new.unset?, "true")

# --- arguments with no constructor raise, naming the fix ---
+ InitHook
  -> init(@label)
  -> label
    @label
raised = ""
begin
  ih = InitHook.new("hello")
  raised = "NO-RAISE:" + ih.label.to_s()
rescue e
  raised = e.to_s()
check("ctor.init_is_not_a_hook", raised.starts_with?("InitHook.new: no constructor"), "true")
check("ctor.error_names_the_form", raised.include?("-> new(@field)"), "true")
check("ctor.error_says_init_not_hook", raised.include?("not constructor hooks"), "true")

+ InitializeHook
  -> initialize(@label)
  -> label
    @label
raised2 = ""
begin
  InitializeHook.new("hello")
  raised2 = "NO-RAISE"
rescue e2
  raised2 = e2.to_s()
check("ctor.initialize_is_not_a_hook", raised2.starts_with?("InitializeHook.new: no constructor"), "true")

# A `ro` declaration does not generate a constructor either.
raised3 = ""
begin
  WithField.new("nope")
  raised3 = "NO-RAISE"
rescue e3
  raised3 = e3.to_s()
check("ctor.ro_does_not_generate", raised3.starts_with?("WithField.new: no constructor"), "true")

# Arity is reported from the call site.
raised4 = ""
begin
  Plain.new(1, 2, 3)
  raised4 = "NO-RAISE"
rescue e4
  raised4 = e4.to_s()
check("ctor.reports_arity", raised4.include?("accepts 3 argument"), "true")
