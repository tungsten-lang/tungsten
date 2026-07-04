# much of this code is modeled on crystal

require "set"

module Tungsten
  class Parser < Lexer
    include AST

    # != !== !~ are defined in terms of equality operators
    # || && are not user-definable
    VALID_DEF_NAMES = %i[ID << < <= == === =~ >> > >= + - * / // ~ ~~ % %% & | ^ ** [] []? []= <=> <-> %+ %- %* %** +@ -@ ~@]

    def self.parse(str)
      new(str).parse
    end

    def initialize(str)
      super

      @assigning = []
      @method    = { name: nil, args: [], block: false }
      @arg       = { ivar: false, default: false, splat: false, double_splat: false }
      @scopes    = [Set.new]
    end

    def parse
      skip_indent

      next_token

      parse_expressions.tap { check_for :EOF }
    end

    def parse_expressions
      expressions = []

      until @token.type?(:EOF)
        expressions << parse_expression
        skip_statement_end
      end

      List.from expressions
    end

    def parse_expression
      exp = parse_assignment
      exp = parse_expression_suffix(exp)
      exp
    end

    # expression suffix must terminate the line
    def parse_expression_suffix(exp)
      skip_space

      return exp unless @token.suffix?

      keyword = @token.value

      next_token

      suffix = parse_assignment_no_control

      exp = case keyword
            when :if
              If.new(suffix, exp)
            when :unless
              If.new(suffix, nil, exp)
            when :while
              While.new(suffix, exp)
            when :until
              While.new(Not.new(suffix), exp)
            when :rescue
            when :ensure
            else
              unexpected
            end

      check_for :SP, :NL, :EOF

      exp
    end

    def parse_assignment_no_control(allow_ops: true, allow_suffix: true)
      # check_void
      parse_assignment(allow_ops:, allow_suffix:)
    end

    def parse_assignment(allow_ops: true, allow_suffix: true)
      exp = parse_ternary

      while true
        case @token.type
        when :SP
          next_token
        when :"="
          if exp.is_a?(Call) && exp.name == "[]"
            next_token_skip_whitespace

            exp.name = "[]="
            exp.args << parse_assignment_no_control
          else
            break unless exp.can_assign?

            if exp.is_a?(Path) && inside_def?
              error "dynamic class assigment"
            end

            if exp.is_a?(Var) && exp.name == "self"
              error "can't reassign self"
            end

            if exp.is_a?(Call) && exp.name.match?(/.*[?!]\b/)
              error "methods ending in '?' or '!' are invalid assignment targets"
            end

            # seeing an '=' means assign instead
            exp = Var.new(exp.name) if exp.is_a?(Call)

            next_token_skip_whitespace

            if exp.is_a?(Var) && !var?(exp.name)
              @assigning.push exp.name
              value = parse_assignment_no_control
              @assigning.pop
            else
              value = parse_assignment_no_control
            end

            push_var(exp)

            exp = Assign.new(exp, value)
          end
        when *@token.assignment_operators
          unexpected unless allow_ops

          break unless exp.can_assign?

          if exp.is_a?(Path)
            error "can't reassign a constant"
          end

          if exp.is_a?(Var) && exp.name == "self"
            error "can't reassign self"
          end

          if exp.is_a?(Call) && exp.name != "[]" && !var?(exp.name)
            error "'#{token.type}' before definition of '#{exp.name}'"
          end

          @scopes.last.add exp.name

          method = @token.type.to_s.chop

          next_token_skip_whitespace

          value = parse_assignment_no_control

          exp = AssignOp.new(exp, method, value)
        else
          break
        end

        allow_ops = true
      end

      exp
    end

    def parse_ternary
      condition = parse_range

      while @token.type?(:"?")
        next_token
        consume_whitespace

        true_body = parse_ternary

        consume_whitespace
        consume :":"
        consume_whitespace

        false_body = parse_ternary

        condition = If.new(condition, true_body, false_body, ternary: true)
      end

      condition
    end

    # @todo support open-ended ranges?
    def parse_range
      exp = parse_or

      return exp unless %i[.. ...].include?(@token.type)

      exclusive = @token.type?('...')

      next_token

      right = parse_or

      RangeLiteral.new(exp, right, exclusive:)
    end

    def self.parse_operator(name, next_op, node, operators, right_assoc = false)
      class_eval %Q[
        def parse_#{name}
          left = parse_#{next_op}

          while true
            case @token.type
            when :SP
              next_token
            when #{operators.map { |x| ":'" + x.to_s + "'" }.join(', ') }
              check_void_value(left)

              method = @token.type.to_s

              next_token_skip_whitespace

              right = parse_#{ right_assoc ? name : next_op }
              left = #{node ? node : "Call.new left, method, right" }
            else
              return left
            end
          end
        end
      ]
    end

    parse_operator :or,          :and,         "Or.new left, right",  %i[||]
    parse_operator :and,         :cmp,         "And.new left, right", %i[&&]
    parse_operator :cmp,         :eql,         nil,                   %i[< <= >= > <=>]
    parse_operator :eql,         :logical_or,  nil,                   %i[== !=]
    parse_operator :logical_or,  :logical_and, nil,                   %i[| ^]
    parse_operator :logical_and, :shift,       nil,                   %i[&]
    parse_operator :shift,       :add_or_sub,  nil,                   %i[>> <<]
    parse_operator :add_or_sub,  :mul_or_div,  nil,                   %i[+ - %+ %-]
    parse_operator :mul_or_div,  :pow,         nil,                   %i[* / // % %*]
    parse_operator :pow,         :unary,       nil,                   %i[** %**], right_assoc: true

    def parse_unary
      operator = @token.type

      case operator
      when :"!"
        parse_negation
      when *%i[+ - ~ %+ %-]
        next_token

        unexpected "whitespace following unary operator" if @token.whitespace?

        Call.new(parse_unary, type.to_s)
      else
        parse_atomic_with_method
      end
    end

    def parse_atomic_with_method
      atomic = parse_atomic
      parse_atomic_method_suffix(atomic)
    end

    def parse_atomic_method_suffix(atomic)
      while true
        case @token.type
        # + receiver.id(...args)
        #                       ^-- OR HERE
        #
        # - receiver.id .id
        when :NL
          case atomic
          when ClassDef, ModuleDef, Def
            # no chaining
            break
          else
            # continue chaining
          end

          if check(/\s*\.|\s*#\s.*\n\s*\./)
            next_token_skip_whitespace
          else
            break
          end
        when :"."
          next_token
          check_for :ID

          if @token.value == "is_a?"
            atomic = parse_is_a(atomic)

          elsif @token.value == "responds_to?"
            atomic = parse_responds_to(atomic)

          elsif @token.value == "nil?"
            atomic = parse_nil?(atomic)

          # receiver.id
          else
            name = @token.value.to_s

            # has_parentheses = false
            space_consumed  = true

            # no space allowed for these suffixes
            case peek(1)
            when "["
              # receiver.id[
              next_token
              next
            when "("
              # receiver.id(
              # has_parentheses = true
              space_consumed  = false
            when " ", "\n"
              # receiver.id ...args
              # receiver.id "op"
              # receiver.id ",", ")", "]", "NL", "EOF"
            end

            next_token

            case @token.type
            when :"="
              # Rewrite 'f.x = arg' as 'f.x=(arg)'
              next_token

              # Consider 'f.x=(exp).a.b.c' to be the same as 'f.x = (exp).a.b.c'
              # and not '(f.x = exp).a.b.c'.
              #
              # The exception is a splat, which can only be expanded arguments
              # for the call.
              if @token.type?(:"(")
                # next token is a splat
                if check(/\(\s*[*]/)
                  next_token_skip_space

                  arg = parse_single_arg
                  check_for :")"
                  next_token
                else
                  # receiver.id = (value).a.b.c
                  arg = parse_assignment_no_control
                end
              # receiver.id = expression
              else
                skip_whitespace
                arg = parse_single_arg
              end

              atomic = Call.new(atomic, "#{name}=", arg)

              next

            # @todo implement ||=
            # receiver.id ||= value should be 'receiver.id || receiver.id = value' and not
            # 'receiver.id = receiver.id || value'.
            # when :"||="

            # receiver.id op= value
            when *@token.assignment_operators
              method = @token.type.to_s.chop
              next_token_skip_whitespace
              value = parse_assignment

              call = Call.new(atomic, name)

              atomic = OpAssign.new(call, method, value)
              next
            else
              # receiver.id
              # receiver.id args, ...
              # receiver.id [...] treat as arg
              # receiver.id (...) treat as arg

              call_args = space_consumed ? parse_call_args_space_consumed : parse_call_args

              if call_args
                args       = call_args.args
                block      = call_args.block
                block_arg  = call_args.block_arg
                named_args = call_args.named_args
              else
                args = block = block_arg = named_args = nil
              end
            end

            block = parse_block(block)

            atomic = Call.new(atomic, name, (args || []), block, block_arg, named_args)
          end
        when :"[]="
          error "expected space after ']', e.g. array[i] = value"
        when :"[]"
          check_void_value(atomic)

          next_token_skip_space

          atomic = Call.new(atomic, "[]")
          atomic
        when :"["
          check_void_value(atomic)

          next_token_skip_whitespace

          call_args = parse_call_args_space_consumed(
                        check_plus_and_minus: false,
                        allow_curly: true,
                        end_token: :"]"
                      )

          skip_whitespace

          consume :"]"

          if args
            args       = call_args.args
            block      = call_args.block
            block_arg  = call_args.block_arg
            named_args = call_args.named_args
          end

          if @token.type?(:"?")
            method_name = "[]?"
            next_token_skip_space
          else
            method_name = "[]"
            skip_space
          end

          atomic = Call.new(atomic, method_name, (args || []), block, block_arg, named_args)
        else
          break
        end
      end

      atomic
    end

    def parse_single_arg
      if @token.type?(:"*")
        next_token

        unexpected_token "space not allowed after '*' in *args" if @token.type?(:SP)

        arg = parse_assignment_no_control
        Splat.new(arg)
      else
        parse_assignment_no_control
      end
    end

    # obj.is_a?(Type)
    def parse_is_a(atomic)
      next_token

      if @token.type?(:"(")
        next_token_skip_whitespace

        path = parse_path
        skip_whitespace
        consume :")"

        skip_space
      else
        path = parse_path
      end

      IsA.new(atomic, path)
    end

    def parse_responds_to(atomic)
      next_token

      case @token.type
      when :"("
        next_token_skip_whitespace

        name = parse_responds_to_name
        next_token_skip_whitespace

        consume :")"

        skip_space
      when :SP
        next_token

        name = parse_responds_to_name
        next_token_skip_space
      else
        unexpected "expected space or '('"
      end

      RespondsTo.new(atomic, name)
    end

    def parse_responds_to_name
      unexpected "expected symbol" unless @token.type?(:SYMBOL)

      @token.value.to_s
    end

    def parse_nil?(atomic)
      next_token

      if @token.type?(:"(")
        next_token_skip_whitespace
        consume :")"
        skip_space
      end

      IsA.new(atomic, Path.global("Nil"), nil_check: true)
    end

    def parse_atomic
      case @token.type
      when :"("
        parse_grouped_expression
      when :"["
        parse_array_literal
      when :"{"
        parse_hash

      when :"[]"
        node_and_next_token ArrayLiteral.new

      when :"::"
        parse_global_path
      when :"->"
        parse_def

      when :WORD_ARRAY
        parse_word_array
      when :SYMBOL_ARRAY
        parse_symbol_array

      when :SYMBOL
        node_and_next_token Symbol.new(@token.value)

      when :TRUE
        node_and_next_token Boolean.new(true)
      when :FALSE
        node_and_next_token Boolean.new(false)
      when :NIL
        node_and_next_token NilLiteral.new

      when :CHAR
        node_and_next_token Char.new(@token.value)
      when :DECIMAL
        node_and_next_token Decimal.new(@token.value)
      when :FLOAT
        node_and_next_token Float.new(@token.value)
      when :INT
        node_and_next_token Int.new(@token.value)

      when :CIDR6
        node_and_next_token CIDR6.new(@token.value)
      when :CIDR4
        node_and_next_token CIDR4.new(@token.value)
      when :IP6
        node_and_next_token IP6.new(@token.value)
      when :IP4
        node_and_next_token IP4.new(@token.value)

      when :UUID
        node_and_next_token UUID.new(@token.value)

      when :COLOR
        v = @token.value
        node_and_next_token AST::ColorLiteral.new(v[0], v[1], v[2], v[3])

      when :DATETIME
        node_and_next_token DateTime.new(@token.value)
      when :TIME
        node_and_next_token TimeLiteral.new(@token.value)
      when :DATE
        node_and_next_token Date.new(@token.value)
      when :WEEK
        # range of dates
      when :MONTH
        # range of dates

      when :IVAR
      when :CVAR
      when :CONSTANT
      when :GLOBAL
      when :UNDERSCORE

      when :"$~", :"$?"
      when :MAGIC_INDEX # $[0-9]
      when :MAGIC_LINE
      when :MAGIC_FILE
      when :MAGIC_DIR

      when :KEYWORD
        case @token.value
        when :alias
          parse_alias
        when :begin
          parse_begin
        when :break
          parse_break
        when :case
          parse_case
        when :class
          parse_class
        when :continue
          parse_continue
        when :def
          parse_def
        when :if
          parse_if
        when :in
          parse_in
        when :is
          parse_is
        when :load
          parse_load
        when :next
          parse_next
        when :return
          parse_return
        when :unless
          parse_unless
        when :until
          parse_loop Until
        when :while
          parse_loop While
        when :with
          parse_with
        when :yield
          parse_yield
        else
          unexpected
        end
      when :ID
        parse_var_or_call
      else
        unexpected
      end
    end

    def parse_grouped_expression
      next_token_skip_whitespace

      parse_expression.tap do
        consume :")"
        next_statement
      end
    end

    def parse_negation
      next_token
      unexpected "whitespace following negation" if @token.whitespace?
      Not.new parse_unary
    end

    def parse_var_or_call
      name = @token.value
      next_token

      args  = parse_args
      block = parse_block

      if block
        Call.new(nil, name, args, block)
      else
        args ? Call.new(nil, name, args) : Var.new(name)
      end
    end

    def parse_block
      if @token.type?(:"{")
        parse_block_inline
      elsif @token.type?(:"->")
        parse_block_multiline
      end
    end

    # receiver.method(params) { expressions }
    #                         ^-------------- HERE
    def parse_block_inline
      next_token_skip_space

      args = []
      body = parse_expressions

      consume :"}"

      next_statement

      Block.new(args, body)
    end

    # receiver.method(params) -> (args)
    #   ...expressions        ^-------- HERE
    def parse_block_multiline
      next_token_skip_space

      if @token.type?(:"(")
        next_token_skip_space

        until @token.type?(:")")
          check_for :ID

          args << Arg.new(@token.value)

          next_token_skip_space
          next_token_skip_space if @token.comma?
        end

        next_token
      end

      skip_whitespace

      body = with_indent { parse_expressions }

      Block.new(args, body)
    end

    def parse_yield
      next_token

      Yield.new parse_args
    end

    def parse_args
      case @token.type
      when :"("
        args = []
        next_token_skip_space

        until @token.type?(:")")
          args << parse_expression

          skip_space
          next_token_skip_whitespace if @token.comma?
        end

        next_token_skip_space
        args
      when :SP
        next_token

        case @token.type
        when :CHAR, :DECIMAL, :INT, :FLOAT, :ID, :"(", :"!", :"["
          args = []

          until end_token?
            args << parse_assignment
            skip_space
            if @token.comma?
              next_token_skip_whitespace
            else
              break
            end
          end

          args
        else
          nil
        end
      else
        nil
      end
    end

    def parse_class
      next_token_skip_whitespace

      check_for :NAME

      name = @token.value
      next_token_skip_space

      if @token.type?(:"<")
        next_token_skip_space
        check_for :NAME
        superclass = @token.value
        next_token
      else
        superclass = nil
      end

      skip_statement_end

      body = with_indent { parse_expressions }

      next_token_skip_statement_end

      ClassDef.new(name, body, superclass)
    end

    # -> method
    # -> method(...args)
    #
    # -> receiver.method IS NOT SUPPORTED
    def parse_def
      @super      = false
      @initialize = false

      method = with_isolated_scope do
        parse_def_internal
      end

      method.super      = @super
      method.initialize = @initialize
    end

    def parse_def_internal
      binding.pry
      next_token

      consume :SP

      name = parse_def_name

      next_token

      case @token.type
      when :"("
        next_token_skip_space

        args = parse_def_args

      when :NL, :";"
        # ok to proceed
        args = []
      when :SP
        unexpected "parentheses are mandatory"
      end

      # @todo create assignment nodes for ivar assigns
      #       parse body
      #       concat ivar assigns + body
    end

    def parse_def_name
      check_for *VALID_DEF_NAMES

      case @token.type
      when :ID
        check_valid_def_name

        @token.value
      else
        # operator
        @token.type.to_s
      end
    end

    def parse_def_args
      # @todo ivar assigns
      # @todo default values
      args = []

      index = 0
      splat_index = 0
      double_splat = nil

      until @token.type?(:")")
        arg = parse_arg(args)

        if @token.comma?
          next_token_skip_space
        else
          skip_space
          check_for :")"
        end

        index += 1
      end
    end

    # klass = While | Until
    def parse_loop(klass)
      raise ArgumentError unless [While, Until].include?(klass)

      next_token_skip_space

      condition = parse_assignment_no_control allow_suffix: false

      body = with_indent { parse_expressions }

      klass.new(condition, body)
    end

    private

    def check_for(*types)
      case types
      when ::Array
        unless types.include?(@token.type)
          error "expecting any of these tokens: #{types.join ', '} (not '#{@token.type}')"
        end
      when Symbol
        unless types.include?(@token.type)
          error "expecting token '#{types}' (not '#{@token.type}')"
        end
      end
    end

    def check_valid_def_name
      if %w[is_a? responds_to? nil?].include?(@token.value)
        error "'#{@token.value}' can't be redefined"
      end
    end

    def check_valid_def_args
      name = @method[:name]

      if name.ends_with?("=")
        if name != "[]=" && (args.size != 1 || @method[:splat] || @method[:double_splat])
          error "setter methods must take one argument: '#{name}'"
        elsif @method[:block]
          error "setter methods cannot take a block: '#{name}'"
        end
      end
    end

    def check_void_value(value)
      case value
      when Break, Next, Return
        error "void value expression"
      end
    end

    def consume(*tokens)
      tokens = [tokens] if tokens.is_a?(Symbol)

      while tokens.size > 0
        type = tokens.shift

        error "expected '#{type}'" unless @token.type?(type)
        next_token
      end
    end

    def consume_whitespace
      error "expected whitespace" unless @token.whitespace?
      next_token
    end

    def end_token?
      case @token.type
      when :"}", :"]", :"%}", :EOF
        true
      when :KEYWORD
        %i[else elsif when in rescue ensure then].include?(@token.value)
      else
        false
      end
    end

    def node_and_next_token(node)
      next_token
      node
    end

    def unexpected(msg = nil, token = @token)
      if msg
        error "unexpected token: #{token} (#{msg})"
      else
        error "unexpected token: #{token}"
      end
    end

    def with_indent(&block)
      consume :INDENT

      yield.tap do
        consume :DEDENT
      end
    end

    def with_isolated_scope(create_scope = true, &block)
      return yield unless create_scope

      begin
        @scopes.push(Set.new)
        yield
      ensure
        @scopes.pop
      end
    end
  end
end
