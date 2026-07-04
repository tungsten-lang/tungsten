require "set"

module Tungsten
  class Parser < Lexer
    include AST

    # operator precedance (highest to lowest)
    # ()                    |       | grouping
    # [] []=                |       | element ref, element set
    # ! ~ +                 | right | logical NOT, bitwise complement, unary plus
    # **                    | right | exponentiation
    # -                     | right | unary minus
    # * / %                 | left  | multiplication, division, modulo
    # + -                   | left  | addition (and concatenation), subtraction
    # << >> >>>             | left  | bitwise shift-left, bitwise shift-right
    # &                     | left  | bitwise AND
    # | ^                   | left  | bitwise OR, XOR
    # < <= >= >             | left  | comparison
    # == === != =~ !~ <=>   |       | equality
    # &&                    | left  | logical AND
    # ||                    | left  | logical OR
    # .. ...                |       | range, boolean flip-flops
    # ? :                   | right | conditional
    # rescue                | left  | exception handling modifier
    # =                     | right | assignment
    # **=+= -= *= /= **=    | right | assignment
    # defined?              |       | test variable definition and type
    # :                     | left  | scope resolution
    # .                     | right | method call
    # not                   | right | boolan NOT (low precedence)
    # and or                | left  | boolean AND, boolean OR (low precedence)
    # if unless while until |       | conditional and loop modifiers
    # { ... }               |       | blocks
    # begin end             |       | blocks
    #
    # Top-level expressions
    #   require
    #   in
    #   module
    #   class
    #   def
    #   call
    #   assign
    #   print
    #
    #   expression (interactive-only)
    #
    # parse_file
    # parse_statement_list
    # parse_statement
    #
    # in
    #   parse_in
    # begin
    #   parse_begin
    # load
    #   parse_load
    # module
    #   parse_module
    # class (+)
    #   parse_class
    # def (->)
    #   parse_method
    #
    # parse_expression_list
    # parse_expression
    # parse_op_assign
    # parse_question_colon
    # parse_or
    # parse_and
    # parse_equality
    # parse_cmp
    # parse_logical_or
    # parse_logical_and
    # parse_shift
    # parse_add_or_sub
    # parse_mul_or_div
    # parse_pow
    # parse_atomic_with_method
    # parse_atomic

    def self.parse(code, scopes = [Set.new])
      new(code, scopes).parse
    end

    def initialize(code, scopes)
      super

      @var_scopes = scopes

      @calls_super = false
      @calls_initialize = false
      @calls_previous_def = false

      @uses_block_arg = false
      @assigns_special_var = false

      @def_nest = 0
      @call_args_nest = 0

      @stop_on_yield = 0

      @inside_interpolation = false
      @stop_on_do = false

      @assigned_vars = []

      skip_indent while @token.type == :INDENT
    end

    def parse
      next_token_skip_statement_end
      skip_indent while @token.type == :INDENT

      parse_expressions.tap { check :EOF }
    end

    def parse_statements
      list = []

      while @token.type != :EOF
        list << parse_statement
      end

      List.new list
    end

    def parse_expressions
      preserve_stop_on_do { parse_expressions_internal }
    end

    def parse_expressions_internal
      return Nop.new if end_token?

      exp = parse_multi_assign

      slash_is_regex!
      skip_statement_end

      return exp if end_token?

      list = []
      list.push exp

      loop do
        list << parse_multi_assign
        skip_statement_end
        break if end_token?
      end

      List.from(exps)
    end

    def parse_multi_assign
      location = @token.location

      if @token.type == :*
        lhs_splat_index = 0
        next_token
      end

      last = parse_expression

      last_is_target = multi_assign_target?(last)

      case @token.type
      when :','
        unless last_is_target
          unexpected_token if lhs_splat_index
          error "multiple assignment is not allowed for constants" if last.is_a?(Path)
          unexpected_token
        end
      when :NL, :';'
        unexpected_token if lhs_splat_index && !multi_assign_middle?(last)
        return last unless lhs_splat_index
      else
        if end_token?
          unexpected_token if lhs_splat_index && !multi_assign_middle?(last)
          return last unless lhs_splat_index
        else
          unexpected_token
        end
      end

      list = []
      list << last

      i = 0
      assign_index = -1

      while @token.type == :','
        if assign_index == -1 && multi_assign_middle?(last)
          assign_index = i
        end

        i += 1

        next_token_skip_whitespace

        if @token.type == :*
          error "splat assignment already specified" if lhs_splat_index
          lhs_splat_index = i
          next_token_skip_space
        end

        last = parse_op_assign(allow_ops: false)
        if assign_index == -1 && !multi_assign_target?(last)
          unexpected_token
        end

        list << last
        skip_space
      end

      if assign_index == -1 && multi_assign_middle?(last)
        assign_index = i
      end

      if assign_index == -1
        unexpected_token
      end

      targets = list[0..assign_index].map { |exp| multiassign_left_hand(exp) }

      assign = list[assign_index]
      values = []

      case assign
      when Assign
        targets << multiassign_left_hand(assign.target)
        values << assign.value
      when Call
        assign.name = assign.name[0..-2]
        targets << assign
        values << assign.args.pop
      else
        error "BUG: multiassign index expression can only be Assign or Call"
      end

      if lhs_splat_index
        targets[lhs_splat_index] = Splat.new(targets[lhs_splat_index])
      end

      values.concat list[assign_index + 1..-1]
      if values.size != 1
        if lhs_splat_index
          error "multiple assignment count mismatch", location if targets.size - 1 > values.size
        else
          error "multiple assignment count mismatch", location if targets.size != values.size
        end
      end

      multi = MultiAssign.new(targets, values).at(location)
      parse_expression_suffix multi, @token.location
    end

    def multi_assign_target?(exp)
      case exp
      when Underscore, Var, InstanceVar, ClassVar, Global, Assign
        true
      when Call
        !exp.has_parentheses? && (
             (exp.args.empty? && !exp.named_args) ||
             Lexer.setter?(exp.name) || exp.name == "[]" || exp.name == "[]="
        )
      else
        false
      end
    end

    def multi_assign_middle?(exp)
      case exp
      when Assign
        true
      when Call
        exp.name.end_with? '='
      else
        false
      end
    end

    def multiassign_left_hand(exp)
      if exp.is_a?(Path)
        error "can't assign to constsant in multiple assignment", exp.location
      end

      if exp.is_a?(Call) && !exp.obj && exp.args.empty?
        exp = Var.new(exp.name).at(exp)
      end

      if exp.is_a?(Var)
        if exp.name == "self"
          error "can't reassign self", exp.location
        end

        push_var exp
      end

      exp
    end

    def parse_statement
      case @token.type
      when :in
        parse_class_path
      when :load
      when :print

      when :return
      when :"{"
      end

      parse_expression_statement.tap do
        skip_statement_end
      end
    end

    def parse_class_path
    end

    def parse_expression_statement
      parse_expression.tap do
        skip_statement_end
      end
    end

    def parse_expression
      location = @token.location
      atomic = parse_assignment
      parse_expression_suffixes(atomic, location)
    end

    def parse_expression_suffixes(atomic, location)
      while true
        case @token.type
        when :KEYWORD
          case @token.value
          when :if
            atomic = parse_expression_suffix(location) { |exp| If.new(exp, atomic) }
          when :unless
            atomic = parse_expression_suffix(location) { |exp| If.new(exp, nil, atomic) }
          when :while
            atomic = parse_expression_suffix(location) { |exp| While.new(exp, atomic) }
          when :until
            atomic = parse_expression_suffix(location) { |exp| While.new(Not.new(exp), atomic) }
          when :rescue
          when :ensure
          else
            break
          end
        when :")", :",", :";", :NL, :EOF
          break
        else
          if end_token?
            break
          else
            unexpected_token
          end
        end
      end

      atomic
    end

    def parse_expression_suffix(location)
      slash_is_regex!
      next_token_skip_statement_end
      exp = parse_assignment_no_control
      (yield exp).at(location)
    end

    def parse_assignment_no_control(allow_ops = true, allow_suffix = true)
      check_void_expression_keyword
      parse_assignment(allow_ops, allow_suffix)
    end

    def parse_assignment(allow_ops = true, allow_suffix = true)
      location = @token.location
      start_token = @token

      atomic = parse_question_colon

      while true
        atomic.location = @token.location

        case @token.type
        when :KEYWORD
          unexpected_token unless allow_suffix
          break
        when :"="
          slash_is_regex!

          if atomic.is_a?(Call) && atomic.name == "[]"
            next_token_skip_whitespace

            atomic.name = "[]="
            atomic.args << parse_assignment_no_control
          else
            break unless atomic.can_assign?

            if atomic.is_a?(Name) && inside_def?
              error "dynamic constant assignment. Constants can only be declared at the top-level."
            end

            if atomic.is_a?(Var) && atomic.name == "self"
              raise "can't reassign self", location
            end

            if atomic.is_a?(Call) && (atomic.name.end_with?('?') || atomic.name.end_with?('!'))
              unexpected_token token: start_token
            end

            atomic = Var.new(atomic.name).at(atomic) if atomic.is_a?(Call)

            next_token_skip_whitespace

            # Constants need a new scope for their value
            case atomic
            # when Path
            #   needs_new_scope = true
            # when InstanceVar
            #   needs_new_scope = @def_nest == 0
            # when ClassVar
            #   needs_new_scope = @def_nest == 0
            when Var
              @assigns_special_var = true if atomic.special_var?
            else
              needs_new_scope = false
            end

            atomic_value = with_isolated_var_scope(needs_new_scope) do
              if @token.type == :KEYWORD && @token.value == :uninitialized && atomic.is_a?(Var)
                push_var atomic
                next_token_skip_space
                type = parse_bare_proc_type
                atomic = UninitializedVar.new(atomic, type).at(location)
                return atomic
              else
                if atomic.is_a?(Var) && !var?(atomic.name)
                  # track variables being assigned to prevent usage in value expression
                  @assigned_vars.push atomic.name
                  value = parse_assignment_no_control
                  @assigned_vars.pop
                  value
                else
                  parse_assignment_no_control
                end
              end
            end

            push_var atomic

            atomic = Assign.new(atomic, atomic_value).at(location)
          end
        when @token.assignment_operator?
          unexpected_token unless allow_ops

          break unless atomic.can_assign?

          if atomic.is_a?(Path)
            error "can't reassign a constant"
          end

          if atomic.is_a?(Var) && atomic.name == "self"
            raise "can't reassign self", location
          end

          if atomic.is_a?(Call) && atomic.name != "[]" && !var_in_scope?(atomic.name)
            error "'#{@token.type}' before definition of '#{atomic.name}'"
          end

          push_var atomic

          method = @token.type.to_s[0..-2]
          next_token_skip_whitespace

          value = parse_assignment_no_control
          atomic = AssignOp.new(atomic, method, value).at(location)
        else
          break
        end

        allow_ops = true
      end

      atomic
    end

    def parse_question_colon
      cond = parse_range

      while @token.type == :"?"
        location = @token.location

        check_void_value cond, location

        @no_type_declaration += 1
        true_val = parse_question_colon

        skip_whitespace

        check :":"

        next_token_skip_whiespace
        false_val = parse_question_colon

        @no_type_declaration -= 1

        cond = If.new(cond, true_val, false_val, ternary: true).at(cond)
      end
    end

    def parse_range
      exp = parse_or
      exp
    end

    def self.parse_operator(name, next_operator, *operators)
      class_eval %Q[
        def parse_#{name}
          location = @token.location

          left = parse_#{next_operator}

          while true
            left.location = location

            case @token.type
            when #{operators.map { |x| ':"' + x.to_s + '"' }.join(',') }
              method = @token.type
              next_token_skip_whitespace
              right = parse_#{next_operator}
              left = Call.new(left, method, [right])
            else
              return left
            end
          end
        end
      ]
    end

    parse_operator :or,          :and,          :'||'
    parse_operator :and,         :equality,     :'&&'

    def parse_equality
      location = @token.location

      left = parse_comparison

      while true
        left.location = location

        case @token.type
        when :==
          next_token_skip_whitespace
          right = parse_comparison
          left = Call.new(left, :==, [right])
        when :!=
          next_token_skip_whitespace
          right = parse_comparison
          left = Not.new(Call.new(left, :==, [right]))
        else
          return left
        end
      end
    end

    def parse_comparison
      location = @token.location

      left = parse_logical_or

      while true
        left.location = location

        case @token.type
        when :<, :<=, :>, :>=
          operator = @token.type

          next_token_skip_whitespace
          right = parse_logical_or
          left = BinaryOp.new(left, operator, right)
        else
          return left
        end
      end
    end

    parse_operator :logical_or,  :logical_and,  :|, :^
    parse_operator :logical_and, :shift,        :&
    parse_operator :shift,       :add_subtract, :<<, :>>

    def parse_add_subtract
      location = @token.location
      left = parse_multiply_divide

      while true
        left.location = location

        case @token.type
        when :+, :-
          method = @token.type

          next_token_skip_whitespace

          right = parse_multiply_divide
          left = Call.new(left, method, [right])
        when :INT
          case @token.value[0]
          when '+', '-'
            left = Call.new(left, @token.value[0].to_sym, [Int.new(@token.value)])
            next_token_skip_whitespace
          else
            return left
          end
        else
          return left
        end
      end
    end

    parse_operator :multiply_divide, :pow, :*, :/, :%
    parse_operator :pow, :atomic_with_method, :**

    def parse_atomic_with_method
      atomic = parse_atomic
      atomic
    end

    def parse_atomic
      case @token.type
      when :'('
        next_token_skip_whitespace
        parse_expression.tap do
          consume :')', "missing right paren ')'."
          skip_statement_end
        end
      when :'[]'
        next_token_skip_whitespace
        ArrayLiteral.new
      when :'['
        next_token_skip_whitespace
        list = []

        while @token.type != :']'
          list << parse_expression
          skip_space

          if @token.type == :','
            next_token_skip_whitespace
          end
        end

        next_token_skip_space

        ArrayLiteral.new list
      when :'!'
        next_token_skip_whitespace
        Call.new(parse_expression, :"!@")
      when :'+'
        next_token_skip_whitespace
        Call.new(parse_expression, :"+@")
      when :'-'
        next_token_skip_whitespace
        Call.new(parse_expression, :"-@")
      when :'~'
        next_token_skip_whitespace
        Call.new(parse_expression, :"~@")
      when :'->'
        parse_def
      when :INT
        node_and_next_token Int.new(@token.value)
      when :DECIMAL
        node_and_next_token Decimal.new(@token.value)
      when :FLOAT
        node_and_next_token Float.new(@token.value)
      when :CHAR
      when :KEYWORD
        case @token.value
        when :begin
          parse_begin
        when :nil
          node_and_next_token Nil.new
        when :false
          node_and_next_token Boolean.new(false)
        when :true
          node_and_next_token Boolean.new(true)
        when :yield
          parse_yield
        when :class
          parse_class
        when :if
          parse_if
        when :unless
          parse_unless
        when :while
          parse_while
        when :return
          parse_return
        when :next
          parse_next
        when :break
          parse_break
        else
          raise "unexpected keyword: #{@token}"
        end
      when :ID, :NAME
        parse_var_or_call
      else
        raise "unexpected token: #{@token}"
      end
    end

    def parse_def
      next_token

      check_for(*%i[ID = << < <= == != >> > >= + - * / % +@ -@ ~@ & | ^ ** [] []=])

      # parse method name
      receiver = nil
      name = @token.type == :ID ? @token.value : @token.type
      args = []

      next_token_skip_space

      if @token.type == :'.'
        receiver = Var.new(name)
        next_token
        check_for(*%i[ID = << < <= == != >> > >= + - * / % +@ -@ ~@ & | ^ ** [] []=])
        name = @token.type == :ID ? @token.value : @token.type
        next_token
      end

      check_for(*%i[( NL ; EOF])

      # parse arg list
      if @token.type == :'('
        next_token_skip_whitespace

        while @token.type != :')'
          check_identifier

          args << Var.new(@token.value)
          next_token_skip_whitespace

          if @token.type == :','
            next_token_skip_whitespace
          end
        end
      end

      next_token_skip_statement_end

      # parse body
      if @token.type != :INDENT
        body = nil
      else
        skip_indent
        body = push_def(args) { parse_expression_list }
        skip_statement_end
        next_token if @token.type == :DEDENT
      end

      name = :'[ ]' if name == :[] && args && args.length > 0

      Def.new(name, args, body, receiver)
    end

    def parse_var_or_call
      name = @token.value
      # name_column_number = @token.location.col

      next_token

      args  = parse_args
      block = parse_block

      result = if block
        Call.new(nil, name, args, block)
      else
        if args
          Call.new(nil, name, args)
        elsif is_var?(name)
          Var.new(name)
        else
          Call.new(nil, name)
        end
      end

      binding.pry
      result
    end

    def parse_block
      if @token.type == :KEYWORD && @token.value == :do
        parse_block2(false) { check_dedent }
      elsif @token.type == :'{'
        parse_block2(true) { check_for :'}' }
      end
    end

    def parse_block2(oneline = true)
      args = []
      body = nil

      next_token_skip_space

      if @token.type == :|
        next_token_skip_whitespace

        while @token.type != :|
          check_for :ID

          args << Var.new(@token.value)
          next_token_skip_whitespace

          if @token.type == :','
            next_token_skip_whitespace
          end
        end

        next_token_skip_statement_end
        next_token_skip_indent unless oneline
      else
        skip_statement_end
        skip_indent
      end

      push_var(*args)

      body = parse_expression_list

      yield

      next_token_skip_statement_end

      Block.new(args, body)
    end

    def parse_args
      case @token.type
      when :'{'
        nil
      when :'('
        args = []
        next_token_skip_space

        while @token.type != :')'
          args << parse_expression
          skip_space

          if @token.type == :','
            next_token_skip_whitespace
          end
        end

        next_token_skip_space
        @last_call_parens = true
        args
      when :CHAR, :DECIMAL, :INT, :FLOAT, :ID, :'(', :'!'
        args = []

        while !%i[NL ; EOF ) :].include?(@token.type) && !end_token?
          args << parse_assignment
          skip_space

          if @token.type == :','
            next_token_skip_whitespace
          else
            break
          end

          args
        end
      end
    end

    def is_var?(name)
      @def_vars.last.include?(name)
    end

    def var?(name)
      name = name.to_s
      name == "self" || var_in_scope?(name)
    end

    def var_in_scope?(name)
      @var_scopes.last.include? name
    end

    def push_def(args)
      @def_vars.push(Set.new(args.map(&:name)))

      yield.tap do
        @def_vars.pop
      end
    end

    def push_vars(vars)
      vars.each do |var|
        push_var var
      end
    end

    def push_var(var)
      case var
      when Var, Arg
        push_var_name var.name.to_s
      # when TypeDeclaration
      else
        # do nothing
      end
    end

    def push_var_name(name)
      @var_scopes.last.add name
    end

    def node_and_next_token(node)
      next_token
      node
    end

    private def check_void_expression_keyword
      case @token.type
      when :KEYWORD
        case @token.value
        when :BREAK, :NEXT, :RETURN
          raise "void value expression", @token, @token.value.to_s.size
        else
          # not a void expression
        end
      else
        # not a void expression
      end
    end

    def check(types)
      case types
      when ::Array
        unless types.include?(@token.type)
          error "expecting any of these tokens: #{types.join ', '} (not '#{@token.type}')", @token
        end
      when Symbol
        if @token.type != types
          error "expecting token '#{types}' (not '#{@token.type}')", @token
        end
      end
    end

    def check_token(value)
      unless value == @token.value
        error "expecting token '#{value}' (not '#{@token.value}')", @token
      end
    end

    def check_keyword(value = nil)
      if value
        unless @token.type == :KEYWORD && @token.value == value
          error "expecting identifier '#{value}' (not '#{@token.value}')", @token
        end
      else
        check :KEYWORD
        @token.value.to_s
      end
    end

    def check_const
      check :NAME
      @token.value.to_s
    end

    def check_identifier(value = nil)
      if value
        error "expecting token: #{value}"        unless @token.type == :ID && @token.value == value
      else
        error "unexpected token: #{@token.to_s}" unless @token.type == :ID && @token.value.is_a?(String)
      end
    end

    private def check_for(*types)
      raise "unexpected token '#{@token.type}' (value #{@token.value}): not in (#{types})" unless types.include?(@token.type)
    end

    def parse_expression_list
      list = []

      while @token.type != :EOF && !end_token?
        list << parse_expression
        skip_statement_end
      end

      List.new list
    end

    def unexpected_token(msg = nil, token = @token)
      token_str = token.type.inspect

      if msg
        raise "unexpected token: #{token_str} (#{msg})", @token
      else
        raise "unexpected token: #{token_str}", @token
      end
    end

    def end_token?
      case @token.type
      when :'}', :']', :DEDENT, :EOF
        true
      when :KEYWORD
        case @token.value
        when :do, :end, :else, :elsif, :when, :rescue, :ensure, :then
          # check for keyword attributes
          # !next_comes_colon_space?
          true
        else
          false
        end
      else
        false
      end
    end

    def next_comes_colon_space?
      binding.pry
    end
  end
end
