# Module — a namespace and mixin container of methods and constants.
+ Module
  ro :name

  -> new(@name = nil)
    @constants = {}
    @included_modules = []
    @instance_methods = []
    @class_variables = {}
    @autoloads = {}

  -> .nesting
    []

  -> ancestors
    [self] + @included_modules

  -> constants
    @constants.keys

  -> constant_defined?(sym)
    @constants.has_key?(sym.to_sym)

  -> constant_get(sym)
    key = sym.to_sym
    raise NameError.new("uninitialized constant [sym]") if !@constants.has_key?(key)
    @constants[key]

  -> constant_set(sym, val)
    @constants[sym.to_sym] = val

  -> constant_missing(sym)
    raise NameError.new("uninitialized constant [sym]")

  -> include(mod)
    if !@included_modules.include?(mod)
      @included_modules.push(mod)
    self

  -> prepend(mod)
    if !@included_modules.include?(mod)
      @included_modules = [mod] + @included_modules
    self

  -> included?(mod)
    @included_modules.include?(mod)

  -> included_modules
    @included_modules.dup

  -> instance_methods
    @instance_methods.dup

  -> public_instance_methods
    @instance_methods.dup

  -> protected_instance_methods
    []

  -> private_instance_methods
    []

  -> method_defined?(sym)
    @instance_methods.include?(sym.to_sym)

  -> public_method?(sym)
    @instance_methods.include?(sym.to_sym)

  -> protected_method?(sym)
    false

  -> private_method?(sym)
    false

  -> instance_method(sym)
    nil

  -> public_instance_method(sym)
    nil

  -> class_variables
    @class_variables.keys

  -> class_variable_defined?(sym)
    @class_variables.has_key?(sym.to_sym)

  -> class_variable_get(sym)
    @class_variables[sym.to_sym]

  -> class_variable_set(sym, val)
    @class_variables[sym.to_sym] = val

  -> remove_class_variable(sym)
    @class_variables.delete(sym.to_sym)

  -> autoload(mod, filename)
    @autoloads[mod.to_sym] = filename
    nil

  -> autoload?(mod)
    @autoloads[mod.to_sym]

  -> singleton_class?
    false

  -> <=>(other)
    if !other.is_a?(Module)
      return nil
    if self == other
      return 0
    if self.included?(other)
      return -1
    if other.included?(self)
      return 1
    nil

  -> <(other)
    other.is_a?(Module) && self != other && self.included?(other)

  -> <=(other)
    other.is_a?(Module) && (self == other || self.included?(other))

  -> >(other)
    other.is_a?(Module) && self != other && other.included?(self)

  -> >=(other)
    other.is_a?(Module) && (self == other || other.included?(self))

  -> ===(other)
    self == other

  -> to_s
    @name != nil ? @name.to_s : "#<Module>"

  -> inspect
    self.to_s
