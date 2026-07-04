require "set"

module Tungsten
  class Parser < Lexer
    include AST

    def self.parse(code)
      new(code).parse
    end

    def initialize(code)
      super

      @scopes    = [Set.new]
      @assigning = []
    end

    def check_for(types)
      case types
      when ::Array
        if types.exclude?(@token.type)
          error "expecting any of these tokens: #{types.join ', '} (not '#{@token.type}')", @token
        end
      when Symbol
        if !@token.type?(types)
          error "expecting token '#{types}' (not '#{@token.type}')", @token
        end
      end
    end

    def check_void
      return unless @token.type?(:KEYWORD)

      case @token.value
      when :break, :next, :return
        error "void value expression", @token, @token.value
      end
    end

    def check_void_value(value)
      case value
      when Break, Next, Return
        error "void value expression"
      end
    end

    def unexpected_token(msg = nil, token = @token)
      token_str = token.to_s.inspect

      if msg
        error "unexpected_token: #{token_str} (#{msg})", @token
      else
        error "unexpected_token: #{token_str}", @token
      end
    end

    def var?(name)
      @scopes.last.include?(name.to_s)
    end

    def parse
      skip_indent while @token.type?(:INDENT)

      next_token

      parse_expressions.tap { check_for :EOF }
    end

    def parse_expressions
      list = []

      until @token.type?(:EOF)
        list << parse_expression
        skip_statement_end
      end

      List.from list
    end

    def parse_expression
      exp = parse_assignment
      exp = parse_expression_suffix(exp) if @token.suffix?
      exp
    end

    # expression suffix must terminate the line
    # @todo support interpolation
    # @todo parse comments following expression suffix
    def parse_expression_suffix(exp)
      next_token if @token.type?(:SP)

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
              unexpected_token
            end

      check_for :NL, :EOF

      exp
    end

    def parse_assignmnt_no_control(allow_ops: true, allow_suffix: true)
      check_void
      parse_assignment(allow_ops:, allow_suffix:)
    end

    def parse_assignment(allow_ops: true, allow_suffix: true)
      exp = parse_ternary

      while true
        case @token.type
        when :SP
          next_token
          next
        when :KEYWORD
          unexpected_token unless allow_suffix
          break
        when :"="
          if exp.is_a?(Call) && exp.name == "[]"
            next_token_skip_whitespace

            exp.name = "[]="
            exp.args << parse_assignment_no_control
          else
            break unless exp.can_assign?

            if exp.is_a?(Path) && inside_def?
              error "dynamic class assignment"
            end

            if exp.is_a?(Var) && exp.name == "self"
              error "can't reassign self"
            end

            if exp.is_a?(Call) && exp.name.match?(/.*[?!]$/)
              error "methods ending in '?' or '!' are invalid assignment targets"
            end

            # seeing an "=" means assign instead
            exp = Var.new(exp.name) if exp.is_a?(Call)

            next_token_skip_whitespace

            if exp.is_a?(Var) && !var?(exp.name)
              @assigning.push exp.name
              value = parse_assignment_no_control
              @assigning.pop
            else
              value = parse_assignment_no_control
            end

            push_var exp

            exp = Assign.new(exp, value)
          end
        when @token.assignment_operator?
          unexpected_token unless allow_ops

          break unless exp.can_assign?

          if exp.is_a?(Path)
            error "can't reassign a constant"
          end

          if exp.is_a?(Var) && exp.name == "self"
            error "can't reassign self"
          end

          if exp.is_a?(Call) && exp.name != "[]" && !var?(exp.name)
            error "'#{@token.type}' before definition of '#{exp.name}'"
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
      cond = parse_range

      while @token.type?(:"?")
        check_void_value(cond)

        next_token_skip_whitespace

        true_body = parse_ternary

        skip_whitespace

        check_for :":"

        next_token_skip_whitespace

        false_body = parse_ternary

        cond = If.new(cond, true_body, false_body, ternary: true)
      end

      cond
    end

    # @todo support open-ended ranges?
    def parse_range
      exp = parse_or

      return exp unless %i[.. ...].include?(@token.type)

      exclusive = @token.type?(:'...')

      # @todo is this necessary?
      check_void_value(exp)

      next_token

      check_void

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

    # @todo support & and *
    def parse_unary
      type = @token.type

      case type
      when %i[! + - ~ %+ %-]
        next_token

        unexpected_token "unary operators cannot be followed by a space"   if @token.type?(:SP)
        unexpected_token "unary operators cannot be followed by a newline" if @token.type?(:NL)

        check_void

        arg = parse_unary

        if type == :"!"
          Not.new(arg)
        else
          Call.new(arg, type.to_s)
        end
      else
        parse_atomic_with_method
      end
    end

    def parse_atomic_with_method
      atomic = parse_atomic
      parse_atomic_method_suffix(atomic)
    end

    # receiver.id(...args)
    # receiver.id  (exp).a.b.c
    # receiver.id (*exp).a.b.c
    # receiver.id[i]
    # receiver.id[i] = value
    # reeciver.id
    #         .id
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

          if check /\s*\.|\s*#\s.*\n\s*\./
            next_token_skip_whitespace
            next
          else
            break
          end

        # receiver.id(...args)
        #         ^-------- HERE
        # receiver.id.id
        #            ^-- OR HERE
        #         .id
        #         ^----- OR HERE
        when :"."
          check_void_value(atomic)

          next_token

          check_for :ID

          # receiver.is_a?
          if @token.value == "is_a?"
            atomic = parse_is_a(atomic)

          # receiver.responds_to?
          elsif @token.value == "responds_to?"
            atomic = parse_responds_to(atomic)

          # receiver.nil?
          elsif @token.value == "nil?"
            atomic = parse_nil(atomic)

          # receiver.id
          else
            name = @token.value.to_s

            has_parentheses = false
            space_consumed  = true

            # no space allowed for these suffixes
            case peek(1)
            when :"["
              # receiver.id[
              next_token
              next
            when :"("
              # receiver.id(
              has_parentheses = true
              space_consumed  = false
            when :" ", :"\n"
              # receiver.id ...args
              # receiver.id "op"
              # receiver.id ",", ")", "]", "NL", or "EOF"
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

          check_for :"]"

          next_token

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

    def parse_atomic_method_suffix_special(call)
      case @token.type
      when :".", :"[", :"[]"
        parse_atomic_method_suffix(call)
      else
        call
      end
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
      next_token_skip_space

      if @token.type?(:"(")
        next_token_skip_whitespace

        path = parse_path
        skip_whitespace
        check_for :")"

        next_token_skip_space
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

        check_for :")"

        next_token_skip_space
      when :SP
        next_token

        name = parse_responds_to_name
        next_token_skip_space
      else
        unexpected_token "expected space or '('"
      end

      RespondsTo.new(atomic, name)
    end

    def parse_responds_to_name
      unexpected_token "expected symbol" unless @token.type?(:SYMBOL)

      @token.value.to_s
    end

    def parse_nil?(atomic)
      next_token

      if @token.type?(:"(")
        next_token_skip_whitespace
        check_for :")"
        next_token_skip_space
      end

      IsA.new(atomic, Path.global("Nil"), nil_check: true)
    end

    # Not implementing parse_negation_suffix
    #
    # receiver.!

    def parse_atomic
      atomic = parse_atomic_without_location
    end

    def parse_atomic_without_location
      case @token.type
      when :"("
        parse_grouped_expression
      when :"[]"
        node_and_next_token ArrayLiteral.new
      when :"["
        parse_array_literal
      when :"{"
        parse_hash
      when :"::"
        parse_generic_or_global_call
      when :"->"
        parse_def
      when :DECIMAL
        node_and_next_token Decimal.new(@token.value.to_s)
      when :INT
        node_and_next_token Int.new(@token.value.to_s)
      when :FLOAT
        node_and_next_token Float.new(@token.value.to_s)
      when :CHAR
        node_and_next_token Char.new(@token.value)
      # when :STRING
      # parse_delimiter
      when :WORD_ARRAY
        parse_word_array
      when :SYMBOL_ARRAY
        parse_symbol_array
      when :SYMBOL
        node_and_next_token Symbol.new(@token.value.to_s)
      when :GLOBAL
      when :"$~", :"$?"
      when :MATCH_INDEX # $[0-9]
      when :MAGIC_LINE
      when :MAGIC_FILE
      when :MAGIC_DIR
      when :TRUE
        node_and_next_token TrueLiteral.new
      when :FALSE
        node_and_next_token FalseLiteral.new
      when :KEYWORD
        case @token.value
        when :lib
        when :nil
          node_and_next_token NilLiteral.new
        when :with
          parse_yield_with_scope
        when :private
        when :protected
        when :while
          parse_loop(While)
        when :until
          parse_loop(Until)
        when *%i[alias class def in is load module]
          not_inside_def do
            self.send "parse_#{@token.value}"
          end
        when *%i[begin break case if next return unless yield]
          self.send "parse_#{@token.value}"
        else
          set_visibility parse_var_or_call
        end
      when :CONSTANT
        parse_constant
      when :IVAR
      when :CVAR
      when :UNDERSCORE
        node_and_next_token Underscore.new
      else
        # unexpected
      end
    end

    def parse_loop(klass)
      next_token_skip_whitespace

      cond = parse_assignment_no_control allow_suffix: false

      check_for :INDENT
      next_token

      body = parse_expressions

      check_for :DEDENT
      next_token_skip_space

      klass.new(cond, body)
    end

    # + ClassName < Superclass
    #   ... body
    #
    def parse_class
      next_token_skip_space

      name = parse_path
      skip_space

      case @token.type
      when :"<"
        next_token_skip_space

        if @token.keyword?("self")
          superclass = Self.new
          next_token
        else
          superclass = parse_path
        end
      when :NL
        next_token_skip_whitespace
      else
        unexpected_token
      end

      check_for :INDENT
      next_token

      body = parse_expressions

      check_for :DEDENT

      next_token_skip_whitespace

      ClassDef.new(name, body, superclass)
    end

    def parse_grouped_expression
      next_token_skip_whitespace

      if @token.type?(:")")
        node = List.from([Nop.new])
        return node_and_next_token(node)
      end

      list = []

      while true
        list << parse_expression
        case @type.type
        when :")"
          next_token_skip_space
          break
        when :NL, :";"
          next_statement

          if @token.type?(:")")
            next_token_skip_space
            break
          end
        else
          error "no matching ')'"
        end
      end

      unexpected_token if @token.type?(:"(")

      List.from(list)
    end

    def parse_word_array(klass)
      list = []

      while true
        next_word_array_token

        case @token.type
        when :STRING
          list << klass.new(@token.value.to_s)
        when :"]"
          next_token
          break
        else
          error "unterminated #{klass.to_s.downcase} array"
        end
      end

      ArrayLiteral.new(list)
    end

    def parse_array_literal
      list = []

      open("array literal") do
        next_token_skip_whitespace

        while !@token.type?(:"]")
          if @token.type?(:"*")
            next_token_skip_whitespace
            exp = Splat.new(parse_assignment_no_control)
          else
            exp = parse_assignment_no_control
          end

          list << exp

          skip_space

          if @token.type?(:",")
            next_token_skip_whitespace
          else
            skip_whitespace
            check_for :"]"
            break
          end
        end

        next_token_skip_space
      end

      ArrayLiteral.new(list)
    end

    def end_token?
      case @token.type
      when :'}', :']', :'%}', :EOF
        true
      when :KEYWORD
        %i[do end else elsif when in rescue ensure then].include?(@token.value)
      else
        false
      end
    end
  end
end
