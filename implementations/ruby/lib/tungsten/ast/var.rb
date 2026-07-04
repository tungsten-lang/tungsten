module Tungsten::AST
  # A local variable, instance variable, constant,
  # or def or block argument.
  class Var < Node
    attr_accessor :name
    attr_accessor :cached_env, :cached_slot  # inline variable cache: env identity + slot index
    attr_accessor :cached_layout_shape       # inline cache across equivalent method frames
    attr_accessor :cached_dispatch_owner, :cached_dispatch_version, :cached_w_method

    def initialize(name)
      @name = Tungsten::AST.intern_name(name)
      @cached_slot = -1
      @cached_layout_shape = 1
    end

    def can_assign?
      true
    end

    def children; end

    def constant?
      return @constant_name if instance_variable_defined?(:@constant_name)

      first = name[0]
      @constant_name = first == first.upcase
    end

    def ==(other)
      super && other.name == name
    end

    def clone
      self.class.new(name).tap do |node|
        node.location = location
      end
    end

    def special_var?
      @name.start_with?("$")
    end
  end
end
