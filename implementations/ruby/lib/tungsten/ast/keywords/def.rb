# Grammar for method definitions (Def) and anonymous lambdas:
#
#   method_def   := '->' SP name '(' params ')' body      # named method
#                 | '->' SP name '/' INT                   # arity method (no body, or ...)
#                 | '->' SP name '/' INT SP expression     # arity method with inline body
#                 | '->' SP? '(' params ')' body           # anonymous lambda
#                 | '->' SP? '(' params ')' SP expression  # anonymous lambda, inline
#                 | 'fn' SP name '(' params ')' body       # pure function (memoized)
#                 | 'fn' SP name '/' INT                   # pure function with arity
#
#   params       := param (',' param)*
#   param        := name                                   # required param
#                 | name '=' expression                    # optional param (default)
#                 | '@' name                               # ivar-assigning param
#                 | '*' name                               # splat (rest args)
#                 | '**' name                              # double splat (keyword rest)
#                 | '&' name                               # block param
#
#   body         := NEWLINE INDENT expressions DEDENT      # indented block
#                 | SP expression                          # inline body (single expr)
#
#   name         := ID | ID_WITH_ARITY | operator
#   operator     := '<<' | '>>' | '+' | '-' | '*' | '/' | '%'
#                 | '**' | '==' | '===' | '<=>' | '[]' | '[]=' | ...
#
# Examples:
#
#   -> greet(name)                     # named, one param, block body
#     << "hello [name]"
#
#   -> add/2 @1 + @2                   # arity, inline body
#
#   -> +(other)                        # operator method
#     self.value + other.value
#
#   ->(x, y) x + y                     # anonymous lambda, inline
#
#   ->(x)                              # anonymous lambda, block body
#     x * 2
#
#   fn fib(n)                          # pure function (auto-memoized)
#     if n <= 1
#       n
#     else
#       fib(n - 1) + fib(n - 2)
#
#   -> [](i)                           # index operator
#     @items[i]
#
#   -> []=(i, value)                   # index assignment operator
#     @items[i] = value
#
module Tungsten::AST
  class Def < Node
    attr_accessor :name, :args, :body

    attr_accessor :receiver, :block, :yields, :splat_index, :double_splat
    attr_accessor :instances, :owner

    # Phase 3 method signature annotations. Both are optional. When
    # present they flow to the compiler's child_var_types / fn_return_types
    # the same way the existing `##` type-hint path does.
    #
    #   param_types: Array[Symbol] — one type symbol per positional param
    #   return_type: Symbol — the declared return type
    attr_accessor :param_types, :return_type

    def initialize(name, args, body, receiver: nil, block: nil, yields: nil, splat_index: nil, double_splat: nil)
      @name = Tungsten::AST.intern_name(name)
      @args = args
      @body = List.from(body)

      @receiver     = receiver
      @block        = block
      @yields       = yields
      @splat_index  = splat_index
      @double_splat = double_splat
      @param_types  = nil
      @return_type  = nil
    end

    def children
      yield @receiver if @receiver.is_a?(Node)
      @args&.each { |arg| yield arg if arg.is_a?(Node) }
      yield @double_splat if @double_splat.is_a?(Node)
      yield @block if @block.is_a?(Node)
      yield @body if @body.is_a?(Node)
    end

    def accept_children(visitor)
      children { |child| child.accept visitor }
    end

    def add_instance(a_def)
      @instances ||= {}
      @instances[a_def.args.map(&:type)] = a_def
    end

    def clone
      self.class.new(name, args.map(&:clone), body.clone, receiver: receiver.clone, block: block.clone, yields:, splat_index:, double_splat: double_splat.clone).tap do |node|
        node.location = location
        # @todo
        # super?
        # new?
        # calls_previous_def?
        # uses_block_arg?
        # assigns_special?
        # visibility
      end
    end

    def lookup_instance(arg_types)
      @instances = @instances[arg_types]
    end

    def mangled_name
      self.class.mangled_name(owner, name, args.map(&:type))
    end

    def self.mangled_name(owner, name, arg_type)
      mangled_args = arg_types.map(&:name).join(', ')

      if owner
        "#{owner.name}##{name}<#{mangled_args}>"
      else
        "#{name}<#{mangled_args}>"
      end
    end

    def ==(other)
      super && other.name         == name         &&
               other.args         == args         &&
               other.body         == body         &&
               other.receiver     == receiver     &&
               other.block        == block        &&
               other.yields       == yields       &&
               other.splat_index  == splat_index  &&
               other.double_splat == double_splat
    end
  end
end
