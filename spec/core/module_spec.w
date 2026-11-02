# Module — the reflection surface declared in core/module.w.
#
# Run:
#   bin/tungsten run --interpret spec/core/module_spec.w
#   bin/tungsten -o /tmp/module_spec spec/core/module_spec.w && /tmp/module_spec

use core/module

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()
  << "PASS " + name

m = Module.new

check("new constructs", type(m) == "Module")
check("is_a? Module", m.is_a?(Module))
check("class_name", m.class_name == "Module")
check("class is Module", m.class == Module)
check("== is reflexive", m == m)
check("hash is stable", m.hash == m.hash)
check("hash is an integer", type(m.hash) == "Int")
check("to_s is a non-empty string", type(m.to_s) == "String" && m.to_s.size > 0)
check("to_s mentions the class", m.to_s.include?("Module"))
check("a Module is not a BlankSlate instance", !m.is_a?(BlankSlate))

check("name", Module.new.name == nil)
check("ancestors", Module.new.ancestors.size > 0)
check("constants is a list", type(Module.new.constants) == "Array")
check("included_modules", type(Module.new.included_modules) == "Array")
check("instance_methods", type(Module.new.instance_methods) == "Array")
check("method_defined?", !Module.new.method_defined?(:nope))
check("singleton_class?", !Module.new.singleton_class?)
check("inspect", type(Module.new.inspect) == "String")
check("distinct instances differ", !(Module.new == Module.new))

<< "ALL PASS module_spec ([passed.load()] checks)"
