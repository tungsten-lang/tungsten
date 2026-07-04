module Tungsten::AST
  # A method call.
  #
  #     [ obj '.' ] name '('                  ')' [ block ]
  #     [ obj '.' ] name '(' arg ( ',' arg )* ')' [ block ]
  #     [ obj '.' ] name     arg ( ',' arg )*     [ block ]
  #
  # An infix method all.
  #
  #     arg name arg
  class Call < Node
    attr_accessor :obj, :name, :args, :block, :target_def, :default

    attr_accessor :has_parens
    attr_accessor :cached_env, :cached_slot
    attr_accessor :cached_layout_shape
    attr_accessor :cached_dispatch_owner, :cached_dispatch_version, :cached_w_method
    attr_accessor :cached_local_miss_shape
    attr_accessor :cached_name_sym  # spinel-only: sym id for @name; -1 sentinel = not yet cached

    def initialize(obj, name, args = [], block = nil, column: nil, parens: false)
      @obj = obj

      @name = Tungsten::AST.intern_name(name)
      @cached_name_sym = -1
      @cached_slot = -1
      @cached_layout_shape = 1

      @args =
        if args.nil?
          []
        elsif args.is_a?(::Array)
          args.any?(::Array) ? args.flatten : args
        else
          [args]
        end

      @block = block

      @name_column_number = column
      @has_parens = parens
    end

    def children
      yield @obj if @obj.is_a?(Node)
      @args.each { |arg| yield arg if arg.is_a?(Node) }
      yield @block if @block.is_a?(Node)
    end

    def accept_children(visitor)
      children { |child| child.accept visitor }
    end

    def can_assign?
      obj.nil? && args.empty? && block.nil?
    end

    def ==(other)
      super && other.obj   == obj &&
               other.name  == name &&
               other.args  == args &&
               other.block == block
    end

    def clone
      self.class.new(obj.clone, name, args.map(&:clone), block.clone).tap do |node|
        node.location = location
      end
    end

    def name_column_number
      @name_column_number || location.col
    end
  end
end
