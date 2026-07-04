module Tungsten
  class Visitor
    def self.register(name)
      define_method name do
        true
      end

      define_method "#{name}_end" do
      end
    end

    def visit_any(node)
    end

    # Default handler for _end methods and unregistered node types.
    # Returns true (continue traversal) for visit methods,
    # nil for end methods.
    def method_missing(name, *args)
      if name.end_with?("_end")
        nil
      else
        true
      end
    end

    def respond_to_missing?(name, include_private = false)
      true
    end
  end
end
