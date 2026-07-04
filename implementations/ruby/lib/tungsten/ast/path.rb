module Tungsten::AST
  class Path < Node
    attr_accessor :names
    attr_accessor :global

    def initialize(names, global = false)
      case names
      when Array
        @names = names.map { |name| Tungsten::AST.intern_name(name) }
      else
        @names = [Tungsten::AST.intern_name(names)]
      end

      @global = global
    end

    def self.global(names)
      new names, true
    end

    def children; end

    def single?(name)
      names.size == 1 && names.first == name
    end

    def single_name?
      names.first if names.size == 1 && !global?
    end

    def clone_without_location
      Path.new(@names.clone, @global)
    end
  end
end
