module Tungsten::AST
  # Assign expression
  #
  #     name '=' value
  #
  class Assign < Node
    attr_accessor :name, :value, :type_hint
    attr_accessor :cached_env, :cached_slot, :cached_layout_shape

    def initialize(name, value, type_hint = nil)
      @name = name
      @value = value
      @type_hint = type_hint
      @cached_env = nil
      @cached_slot = -1
      @cached_layout_shape = 0
    end

    def children
      yield @name if @name.is_a?(Node)
      yield @value if @value.is_a?(Node)
    end

    def accept_children(visitor)
      children { |child| child.accept visitor }
    end

    def ==(other)
      super && other.name  == name &&
               other.value == value
    end

    def clone
      self.class.new(name.clone, value.clone).tap do |node|
        node.location = location
      end
    end
  end
end
