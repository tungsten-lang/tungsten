# frozen_string_literal: true

module Tungsten
  module Runtime
    class WClass
      EMPTY_PARAMS = [].freeze

      # Method names that carry a typed overload anywhere in this process —
      # a cheap dispatch-time gate so calls to untyped names never pay for
      # an overload-table walk. Names are never pruned; the per-class
      # @method_overloads table stays authoritative for actual selection.
      @typed_overload_names = {}

      class << self
        attr_reader :typed_overload_names
      end

      attr_accessor :name, :superclass, :methods, :traits, :version, :class_vars, :method_overloads

      def initialize(name, superclass = nil)
        @name = name
        @superclass = superclass
        @methods = {}
        @method_overloads = {}
        @traits = []
        @version = 0
        @class_vars = {}
      end

      def lookup_method(name, argc: nil)
        klass = self
        while klass
          if argc.nil?
            method = klass.methods[name]
            return method if method
          else
            overloads = klass.method_overloads[name]
            if overloads
              method = overloads.reverse_each.find { |candidate| method_accepts_arity?(candidate, argc) }
              return method if method
            end
          end

          klass = klass.superclass
        end
        # Keep the historical name-only fallback for call shapes implemented
        # above ordinary binding (notably implicit construction, where
        # `point.distance(1, 2, 3)` first resolves distance/1 and then wraps
        # the arguments in Point.new). Exact arity always wins across the
        # whole superclass chain before this fallback is considered.
        argc.nil? ? nil : lookup_method(name)
      end

      # Single insertion path for interpreted instance methods, mirroring
      # the self-hosted interpreter's register_instance_method
      # (compiler/lib/interpreter.w): the name map keeps last-definition
      # lookup for callers that carry no argument types; the side table
      # keeps registration order, where same-arity siblings with DIFFERENT
      # declared param types coexist as typed overloads and a same-arity
      # same-param-type redefinition replaces its old slot.
      def define_method(name, method)
        register_overload(name, method)
        WClass.typed_overload_names[name] = true if method.param_types
        @methods[name] = method
        @version += 1
      end

      def include_trait(trait)
        @traits << trait
        changed = false
        trait.methods.each do |mname, method|
          next if @methods.key?(mname)

          register_overload(mname, method)
          @methods[mname] = method
          changed = true
        end
        @version += 1 if changed
      end

      # The nearest class up the chain carrying overload registrations for
      # `name` — returned when any of them is typed, nil otherwise (the
      # common case; an untyped redefinition shadows ancestors' typed
      # groups the same way the name map does).
      def typed_overloads_for(name)
        klass = self
        while klass
          overloads = klass.method_overloads[name]
          if overloads && !overloads.empty?
            return overloads if overloads.any?(&:param_types)

            return nil
          end
          klass = klass.superclass
        end
        nil
      end

      def to_s = name

      private

      def method_accepts_arity?(method, argc)
        params = method.params || EMPTY_PARAMS
        required = params.count { |param| !param.default }
        required -= 1 if method.splat_index
        return argc >= required if method.splat_index

        argc >= required && argc <= params.size
      end

      def register_overload(name, method)
        overloads = (@method_overloads[name] ||= [])
        arity = (method.params || EMPTY_PARAMS).size
        index = overloads.index do |m|
          (m.params || EMPTY_PARAMS).size == arity && m.param_types == method.param_types
        end
        if index
          overloads[index] = method
        else
          overloads << method
        end
      end
    end
  end
end
