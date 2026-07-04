# frozen_string_literal: true

module Tungsten
  module Runtime
    class WClass
      attr_accessor :name, :superclass, :methods, :traits, :version, :class_vars

      def initialize(name, superclass = nil)
        @name = name
        @superclass = superclass
        @methods = {}
        @traits = []
        @version = 0
        @class_vars = {}
      end

      def lookup_method(name)
        klass = self
        while klass
          method = klass.methods[name]
          return method if method

          klass = klass.superclass
        end
        nil
      end

      def define_method(name, method)
        @methods[name] = method
        @version += 1
      end

      def include_trait(trait)
        @traits << trait
        changed = false
        trait.methods.each do |mname, method|
          next if @methods.key?(mname)

          @methods[mname] = method
          changed = true
        end
        @version += 1 if changed
      end

      def to_s = name
    end
  end
end
