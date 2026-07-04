+ Module
  -> constants
  -> nesting

  -> </1
  -> <=/1
  -> <=>/1

  -> ==/1
  -> ===/1

  -> >/1
  -> >=/1

  -> ancestors
  -> autoload(module, filename)
  -> autoload?(name)

  -> class_eval(string, filename = nil, lineno = nil)
  -> class_exec(*args) { … }

  -> class_variable_defined?/1:symbol
  -> class_variable_defined?/1:string

  -> class_variable_get/1:symbol
  -> class_variable_get/1:string

  -> class_variable_set/2

  -> class_variables
  -> constant_defined?/1
  -> constant_get/1
  -> constant_missing/1
  -> constant_set/2
  -> constants

  -> include(module)
  -> included?/1
  -> included_modules
  -> inspect
  -> instance_method/1
  -> instance_methods

  -> method_defined?/1
  -> module_eval { … }
  -> module_exec(*args) { … }

  -> name

  -> prepend/1

  -> private_class_method/*
  -> private_constant/*

  -> private_instance_methods
  -> private_method?/1

  -> protected_instance_methods
  -> protected_method?/1

  -> public_class_method/*
  -> public_constant/*
  -> public_instance_method/1
  -> public_instance_methods
  -> public_method?/1

  -> remove_class_variable/1

  -> singleton_class?

  -> to_s

  private

  -> alias_method(new_name, old_name)
  -> append_features/1
  -> attr/*
  -> attr_accessor/*
  -> attr_reader/*
  -> attr_writer/*

  -> define_method(name, method)
  -> define_method(name) { … }

  -> extend_object/1

  -> extended/1

  -> included/1

  -> method_added/1
  -> method_removed/1
  -> method_undefined/1

  -> module_function/*

  -> prepend_features/1
  -> prepended/1

  -> private
  -> private/*

  -> protected
  -> protected/*

  -> public
  -> public/*

  -> refine

  -> remove_method/1
  -> undef_method/1

  -> using/1
