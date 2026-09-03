# Module — the reflection surface declared in core/module.w.
#
# core/module.w cannot be loaded by either engine (see the BUG note below), so
# this spec exercises the runtime-provided `Module` class that autoload resolves
# without reading the file, and pins the declared surface as BUG notes.
#
# INTERPRETER LANE. Compiled, the constant `Module` itself is nil — `Module.new` raises
# "undefined method 'new' for nil" — because the only definition is the unloadable
# core/module.w. The interpreter supplies a built-in Module class.
# Repro: printf '<< type(Module.new)\n' > /tmp/m.w && bin/tungsten -o /tmp/m /tmp/m.w && /tmp/m
#
# Run:
#   bin/tungsten run --interpret spec/core/module_spec.w

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

# BUG: `use core/module` fails to lex on both engines. Line 20 of core/module.w is
#   -> class_exec(*args) { … }
# and the U+2026 HORIZONTAL ELLIPSIS placeholder is not a legal character:
# "Unexpected character '…'  --> core/module.w:20:26" (E_LEX_UNEXPECTED_CHAR). Three
# declarations use that placeholder (class_exec, module_eval, module_exec) and the file
# also uses the bare `private` keyword the interpreter rejects, so nothing in it loads.
# Repro: printf 'use core/module\n<< 1\n' > /tmp/m.w && bin/tungsten run --interpret /tmp/m.w
#
# BUG: consequently none of the declared reflection surface is reachable — every one of
# these raises "undefined method ... for Module instance" on both engines:
# constants, nesting, ancestors, name, inspect, autoload, autoload?, class_eval,
# class_variable_get/set/defined?, class_variables, constant_get/set/defined?/missing,
# include, included?, included_modules, instance_method, instance_methods,
# method_defined?, prepend, private_instance_methods, private_method?,
# protected_instance_methods, protected_method?, public_instance_method(s),
# public_method?, remove_class_variable, singleton_class?, and the ordering operators
# < <= <=> > >= ===.
# check("name", Module.new.name == nil)
# check("ancestors", Module.new.ancestors.size > 0)
# check("constants is a list", type(Module.new.constants) == "Array")
# check("included_modules", type(Module.new.included_modules) == "Array")
# check("instance_methods", type(Module.new.instance_methods) == "Array")
# check("method_defined?", !Module.new.method_defined?(:nope))
# check("singleton_class?", !Module.new.singleton_class?)
# check("inspect", type(Module.new.inspect) == "String")
#
# BUG: two distinct field-less Module instances compare `==` interpreted and `!=` compiled,
# the same default-equality divergence object_spec.w records.
# check("distinct instances differ", !(Module.new == Module.new))

<< "ALL PASS module_spec ([passed.load()] checks)"
