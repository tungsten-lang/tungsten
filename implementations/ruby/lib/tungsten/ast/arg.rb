module Tungsten::AST
  class Arg < Node
    attr_accessor :name, :external_name, :default, :restriction, :keyword

    # true when the param binds an ivar (`-> new(@x)`); read by the
    # trailing ro/rw accessor marker to know which fields to generate.
    attr_accessor :ivar

    def initialize(name, default = nil, restriction = nil, external_name = nil, keyword: false)
      @name          = Tungsten::AST.intern_name(name)
      @default       = default
      @restriction   = restriction
      @external_name = Tungsten::AST.intern_name(external_name || @name)
      @keyword       = keyword
    end

    def children
      yield @default if @default.is_a?(Node)
      yield @restriction if @restriction.is_a?(Node)
    end

    def accept_children(visitor)
      children { |child| child.accept visitor }
    end

    def name_size
      name.size
    end

    def clone
      copy = Arg.new(@name, @default.clone, @restriction.clone, @external_name.clone, keyword: @keyword)
      copy.ivar = @ivar
      copy
    end

    def ==(other)
      super && other.name          == name          &&
               other.default       == default       &&
               other.restriction   == restriction   &&
               other.external_name == external_name &&
               other.keyword       == keyword
    end
  end
end
