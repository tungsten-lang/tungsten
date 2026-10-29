module Tungsten::AST
  # A local variable, instance variable, constant,
  # or def or block argument.
  class Var < Node
    attr_accessor :name
    attr_accessor :cached_env, :cached_slot  # inline variable cache: env identity + slot index
    attr_accessor :cached_layout_shape       # inline cache across equivalent method frames
    attr_accessor :cached_miss_shape         # inline cache for @root_env hits when current frame misses
    attr_accessor :cached_const_env_version  # inline cache for non-class constant negative lookups
    attr_accessor :cached_dispatch_owner, :cached_dispatch_version, :cached_w_method
    attr_reader :bang_base, :is_self

    def initialize(name)
      @name = Tungsten::AST.intern_name(name)
      @cached_slot = -1
      @cached_layout_shape = 1
      @cached_miss_shape = 1
      @cached_const_env_version = -1
      @is_self = @name == "self"
      @bang_base = @name.end_with?("!") && @name.size > 1 ? -@name.delete_suffix("!") : nil
      first = @name.getbyte(0)
      @constant_name =
        if first.nil? || (first >= 97 && first <= 122)
          false
        elsif first >= 65 && first <= 90
          true
        else
          ch = @name[0]
          ch == ch.upcase
        end
    end

    def eval_in(interp)
      interp.visit_var(self)
    end

    def can_assign?
      true
    end

    def children; end

    def constant?
      @constant_name
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
