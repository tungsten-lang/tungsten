# frozen_string_literal: true

require "set"

module Tungsten
  class Parser < Lexer
    include AST

    # != !== !~ are defined in terms of equality operators
    # || &&     are not user-definable
    # <= < > >= are not user-definable, use <=>
    VALID_METHOD_NAMES = %i[ID ID_WITH_ARITY TYPE KEYWORD << == === =~ >> + - * / // ~ ~~ % %% & | ^ ** [] []? []= <=> <-> %+ %- %* %** +@ -@ ~@]
    EMPTY_ARGS = [].freeze
    SOFT_IDENTIFIER_KEYWORDS = %i[with].freeze

    Unclosed = Struct.new(:name, :file, :row, :col) do
      def location
        Tungsten::Location.new(file, row, col)
      end
    end

    def self.parse(str)
      new(str).parse.set_parents!
    end

    def initialize(str)
      if Tungsten.codepoint_lexer?
        @token = Token.new
        @lexer_adapter = Tungsten.new_lexer(str)
      else
        super
      end

      @assigning = []
      @method    = {}
      @unclosed  = []
      @scopes    = [Set.new]
      @in_class_body = false
      @namespace_prefix = nil

      @nested_methods = 0
    end

    def file=(path)
      @file = path
      @lexer_adapter.file = path if @lexer_adapter
    end

    def error(msg)
      return super unless @lexer_adapter

      row = @token.row || 1
      col = @token.col || 1
      err = Error.new("syntax on line #{row}: #{msg}")
      err.location = Location.new(@file, row, col)
      err.source_code = string
      err.file_path = @file
      raise err
    end

    def next_token
      return super unless @lexer_adapter

      @token = @lexer_adapter.next_token
    end

    def scan(pattern)
      @lexer_adapter ? @lexer_adapter.scan(pattern) : super
    end

    def skip(pattern)
      @lexer_adapter ? @lexer_adapter.skip(pattern) : super
    end

    def check(pattern)
      @lexer_adapter ? @lexer_adapter.check(pattern) : super
    end

    def pos
      @lexer_adapter ? @lexer_adapter.pos : super
    end

    def pos=(new_pos)
      if @lexer_adapter
        @lexer_adapter.pos = new_pos
      else
        super
      end
    end

    def string
      @lexer_adapter ? @lexer_adapter.string : super
    end

    def rest
      @lexer_adapter ? @lexer_adapter.rest : super
    end

    def eos?
      @lexer_adapter ? @lexer_adapter.eos? : super
    end

    def parse
      skip_indent

      next_token

      parse_expressions.tap { check_for :EOF }
    end

    # Set location on an AST node from the current token position.
    def locate(node)
      node.set_location(@token.file, @token.row, @token.col) unless node.location_row
      node
    end

    def parse_expressions
      expressions = []

      next_token if @token.type?(:SHEBANG)

      # @todo confirm this is correct regarding dedents
      until @token.type?(:EOF)
        skip_statement_end
        break if @token.type?(:EOF)
        exp = parse_expression(allow_multi_assign: true)
        expressions << finish_statement_expression(exp)
      end

      List.from expressions
    end

    def parse_body
      expressions = []

      until @token.type?(:DEDENT)
        skip_statement_end
        break if @token.type?(:DEDENT)
        exp = parse_expression(allow_multi_assign: true)
        expressions << finish_statement_expression(exp)
      end

      List.from expressions
    end

    def finish_statement_expression(exp)
      skip_statement_end
      exp = parse_statement_continuations(exp)
      while @token.type?(:"|>")
        exp = parse_pipeline_tail(exp)
        skip_statement_end
        exp = parse_statement_continuations(exp)
      end
      exp
    end

    def parse_statement_continuations(exp)
      loop do
        case @token.type
        when :"."
          exp = parse_continuation_call(exp)
          skip_statement_end
        when :INDENT
          next_token
          skip_statement_end
          until @token.type?(:DEDENT) || @token.type?(:EOF)
            if @token.type?(:".")
              exp = parse_continuation_call(exp)
            elsif @token.type?(:ID) && @token.value == "self"
              exp = parse_continuation_call(exp, consume_self: true)
            else
              unexpected "expected continuation call"
            end
            skip_statement_end
          end
          consume :DEDENT unless @token.type?(:EOF)
          skip_statement_end
        else
          return exp
        end
      end
    end

    def parse_continuation_call(receiver, consume_self: false)
      if consume_self
        error "expected 'self' continuation" unless @token.type?(:ID) && @token.value == "self"
        next_token_skip_space
        check_for :"."
      end

      next_token_skip_space
      check_for :ID, :NAME, :KEYWORD

      name = @token.value.to_s
      name_file = @token.file
      name_row = @token.row
      name_col = @token.col
      next_token

      args = parse_call_args
      block = parse_block

      call = if block
               Call.new(receiver, name, args || [], block)
             else
               args ? Call.new(receiver, name, args) : Call.new(receiver, name)
             end
      call.set_location(name_file, name_row, name_col)
      call
    end

    def parse_expression(allow_multi_assign: false)
      start_row = @token.row
      start_file = @token.file
      start_col = @token.col

      if @in_class_body && @token.type?(:-)
        node = parse_data_declaration
        node.set_location(start_file, start_row, start_col)
        return node
      end

      exp = parse_assignment
      unless exp.location_row
        if (child = first_child_with_location(exp))
          exp.copy_location_from(child)
        else
          exp.set_location(start_file, start_row, start_col)
        end
      end

      # Multi-assignment: a, b = expr  /  a, *rest, b = expr (only at statement level)
      if allow_multi_assign && exp.is_a?(Var) && @token.type?(:",")
        targets = [exp]
        while @token.type?(:",")
          next_token_skip_whitespace
          if @token.type?(:"*")
            next_token_skip_whitespace
            target = parse_ternary
            target = Var.new(target.name) if target.is_a?(Call) && !target.obj && (target.args.nil? || target.args.empty?) && target.block.nil?
            target = Splat.new(target)
          else
            target = parse_ternary
            target = Var.new(target.name) if target.is_a?(Call) && !target.obj && (target.args.nil? || target.args.empty?) && target.block.nil?
          end
          targets << target
        end

        skip_space
        if @token.type?(:"=")
          next_token_skip_whitespace
          value = parse_assignment_no_control
          targets.each do |t|
            t = t.exp if t.is_a?(Splat)
            push_var(t) if t.is_a?(Var)
          end
          loc_file = exp.location_file || start_file
          loc_row = exp.location_row || start_row
          loc_col = exp.location_col || start_col
          exp = Assign.new(ArrayLiteral.new(targets), value)
          exp.set_location(loc_file, loc_row, loc_col)
          return exp
        else
          raise_error "expected '=' after multi-assignment targets"
        end
      end

      # Swap: `a <> b` — desugars to the same destructuring assign the
      # multi-assign path builds: [a, b] = [b, a]. Mirrors the compiled
      # parser's MultiAssign desugar.
      if @token.type?(:"<>")
        exp = Var.new(exp.name) if exp.is_a?(Call) && !exp.obj && (exp.args.nil? || exp.args.empty?) && exp.block.nil?
        raise_error "expected a variable on the left of '<>'" unless exp.is_a?(Var)
        next_token_skip_whitespace
        rhs = parse_ternary
        rhs = Var.new(rhs.name) if rhs.is_a?(Call) && !rhs.obj && (rhs.args.nil? || rhs.args.empty?) && rhs.block.nil?
        raise_error "expected a variable on the right of '<>'" unless rhs.is_a?(Var)
        push_var(exp)
        push_var(rhs)
        value = ArrayLiteral.new([Var.new(rhs.name), Var.new(exp.name)])
        swap = Assign.new(ArrayLiteral.new([Var.new(exp.name), Var.new(rhs.name)]), value)
        swap.set_location(start_file, start_row, start_col)
        return swap
      end

      # Range/Array/Hash followed by -> or { desugars to .each
      if implicit_each?(exp)
        block = parse_block(same_line: start_row)
        if block
          exp = exp.is_a?(Var) && exp.name == "each" ? Call.new(nil, "each", [], block) : Call.new(exp, "each", [], block)
        end
      end

      if @token.type?(:":") && @token.row == start_row
        next_token_skip_space
        exp = Begin.new([exp, parse_assignment_no_control])
      end

      exp = parse_expression_suffix(exp, start_row)
      exp
    end

    def parse_expression_suffix(exp, start_row = @token.row)
      skip_space

      return exp unless @token.suffix?
      return exp if @token.row > start_row
      return exp if exp.is_a?(If) || exp.is_a?(While) || exp.is_a?(Begin) || exp.is_a?(Case)

      keyword = @token.value

      next_token_skip_space

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
              Begin.new(exp, nil, suffix, nil)
            when :ensure # @todo
            else
              unexpected
            end

      check_for :SP, :NL, :EOF, :"=>"

      exp
    end

    def parse_assignment_no_control(allow_ops: true, allow_suffix: true)
      check_void
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
          elsif exp.is_a?(Call) && exp.obj && exp.args.empty? && exp.block.nil?
            # Setter call: receiver.name = value → receiver.name=(value)
            next_token_skip_whitespace
            value = parse_assignment_no_control
            exp = Call.new(exp.obj, "#{exp.name}=", [value])
          else
            break unless exp.can_assign?

            # @todo check if inside def and assigning Path

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

            # Inline type annotation: a = 34 ## i128
            # Inline memory hint:     a = [] ## reuse  /  a = {} ## recycle
            hint = nil
            if @token.type?(:TYPE_HINT)
              hint = @token.value
              next_token
              # Memory hints attach to the RHS allocation node. The Ruby
              # interpreter doesn't implement reuse semantics (heap alloc
              # is fine) but still accepts the hint so files parse cleanly.
              stripped = hint.to_s.strip
              if stripped == "reuse" || stripped == "recycle" || stripped == "reuse_drain"
                if value.respond_to?(:instance_variable_set)
                  value.instance_variable_set(:@reuse_mode, stripped.to_sym)
                end
                hint = nil
              end
            end

            exp = Assign.new(exp, value, hint)
          end
        else
          break unless @token.assignment_operator?

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

          push_var(exp)

          method = @token.type.to_s.chop

          next_token_skip_whitespace

          value = parse_assignment_no_control

          exp = AssignOp.new(exp, method.to_sym, value)
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

        true_body = parse_ternary_branch

        # @todo parse_operator eats the whitespace
        # consume_whitespace
        consume :":"
        consume_whitespace

        false_body = parse_ternary_branch

        # @todo add ternary argument to If.new
        condition = If.new(condition, true_body, false_body)
      end

      condition
    end

    def parse_ternary_branch
      if @token.type?(:KEYWORD)
        keyword = @token.value
        if %i[break next return].include?(keyword)
          next_token
          skip_space
          value = nil
          value = parse_assignment_no_control unless @token.type?(:":")
          return Break.new(value) if keyword == :break
          return Next.new(value) if keyword == :next
          return Return.new(value)
        end
      end

      parse_ternary
    end

    def parse_range
      exp = parse_pipeline

      return exp unless %i[.. ...].include?(@token.type)

      exclusive = @token.type?(:"...")

      next_token

      # Endless range: 1.. (no right-hand side). ARROW matters because
      # `0.. -> ; ...` is the block-iteration form.
      if %i[\] ) , NL ; EOF DEDENT SP ARROW].include?(@token.type)
        return RangeLiteral.new(exp, nil, exclusive:)
      end

      old_suppress = @suppress_block
      @suppress_block = true
      right = parse_or
      @suppress_block = old_suppress

      RangeLiteral.new(exp, right, exclusive:)
    end

    def parse_pipeline
      left = parse_or

      loop do
        next_token while @token.type?(:SP)
        break unless @token.type?(:"|>")

        left = parse_pipeline_tail(left)
      end

      left
    end

    def parse_pipeline_tail(left)
      next_token_skip_whitespace

      if @token.type?(:".") || @token.type?(:"&.")
        return parse_atomic_method_suffix(left)
      end

      pipe_target(left, parse_or)
    end

    def pipe_target(left, target)
      case target
      when Call
        if target.obj.is_a?(Self) || (target.obj.is_a?(Var) && target.obj.name == "self")
          Call.new(left, target.name, target.args, target.block)
        elsif target.obj
          Call.new(target.obj, target.name, [left] + target.args, target.block)
        else
          Call.new(nil, target.name, [left] + target.args, target.block)
        end
      when Var
        Call.new(nil, target.name, [left])
      else
        Call.new(target, "call", [left])
      end
    end

    def self.parse_operator(name, next_op, node, operators, right_assoc = false)
      operator_assignment =
        if node
          ""
        else
          "operator = @token.type"
        end

      left_assignment =
        if node
          node
        else
          "BinaryOp.new(left, operator, right)"
        end

      class_eval %Q[
        def parse_#{name}
          left = parse_#{next_op}

          while true
            case @token.type
            when :SP
              next_token
            when #{operators.map { |x| ":'" + x.to_s + "'" }.join(', ') }
              check_void_value(left)

              #{operator_assignment}

              next_token_skip_whitespace

              right = parse_#{ right_assoc ? name : next_op }
              left = #{left_assignment}
            else
              return left
            end
          end
        end
      ]
    end

    parse_operator :or,          :and,         "Or.new left, right",  %i[||]
    parse_operator :and,         :in_test,     "And.new left, right", %i[&&]

    # `lhs in (a b c)` — membership test with space-separated tuple RHS.
    # Precedence sits between logical `&&` and comparison operators so
    # `c in (0x28 0x29) && other` parses without parentheses around the
    # membership test. Lowered by the compiler to a flat OR chain of
    # equality comparisons.
    def parse_in_test
      left = parse_cmp

      while @token.type == :SP
        next_token
      end

      return left unless @token.type == :KEYWORD && @token.value == :in

      check_void_value(left)
      next_token_skip_whitespace

      unless @token.type == :"("
        error("`in` requires a parenthesized tuple on the right-hand side")
      end
      next_token_skip_whitespace

      elements = []
      # Tuple elements are space-separated values, not paren-less calls:
      # suppress spaced-arg consumption so `(A B)` parses as two elements
      # rather than the call `A(B)`.
      prev_no_spaced = @no_spaced_call_args
      @no_spaced_call_args = true
      begin
        until @token.type == :")"
          if @token.type == :EOF
            error("unterminated `in` tuple")
          end
          elements << parse_cmp
          while @token.type == :SP || @token.type == :NL
            next_token
          end
        end
      ensure
        @no_spaced_call_args = prev_no_spaced
      end

      if elements.empty?
        error("`in` tuple must have at least one element")
      end

      consume :")"
      AST::InTest.new(left, elements)
    end

    parse_operator :cmp,         :eql,         nil,                   %i[< <= >= > <=>]
    parse_operator :eql,         :logical_or,  nil,                   %i[== != =~]
    parse_operator :logical_and, :shift,       nil,                   %i[& .&]

    # Override parse_shift: << at the start of a new line is Print (puts), not binary shift.
    # "<<" is puts anytime it is the first thing on a line; append requires a left-hand side on the same line.
    def parse_shift
      start_row = @token.row
      left = parse_add_or_sub

      while true
        case @token.type
        when :SP
          next_token
        when :">>"
          check_void_value(left)
          method = @token.type
          next_token_skip_whitespace
          right = parse_add_or_sub
          left = BinaryOp.new(left, method, right)
        when :"<<"
          return left if @token.row > start_row
          check_void_value(left)
          method = @token.type
          next_token_skip_whitespace
          right = parse_add_or_sub
          left = BinaryOp.new(left, method, right)
        when :".<<", :".>>"
          # Phase 4e: dot-prefix shifts share shift precedence with the
          # scalar counterparts. Always elementwise — `.<< ` at line start
          # is still a parse error since the lexer requires whitespace
          # AROUND the operator (see CodepointLexer's `when 46` block).
          check_void_value(left)
          method = @token.type
          next_token_skip_whitespace
          right = parse_add_or_sub
          left = BinaryOp.new(left, method, right)
        else
          return left
        end
      end
    end

    # Phase 4e dot-prefix elementwise operators (.+ .- .* ./ .| .& .^
    # .<< .>>) ride at the same precedence as their scalar counterparts
    # (Julia convention).
    parse_operator :add_or_sub,  :mul_or_div,  nil,                   %i[+ - %+ %- .+ .- ±]
    parse_operator :mul_or_div,  :pow,         nil,                   %i[* / // % %* .* ./]
    parse_operator :pow,         :unary,       nil,                   %i[** %**], right_assoc: true

    # Override parse_logical_or to handle | and » with compound unit scanning.
    # After | or », we try scanning a UNIT_STRING (e.g. m/s, kg·m/s²) directly
    # from the raw input. If a compound unit is found, we use it as-is instead
    # of normal expression parsing (which can't handle / or * without spaces).
    def parse_logical_or
      left = parse_logical_and

      while true
        case @token.type
        when :SP
          next_token
        when :|, :"»"
          check_void_value(left)
          method = @token.type

          saved_pos = pos
          scan(/\s+/)
          unit_match = scan(UNIT_STRING)

          # Check for "per" as "/" synonym (e.g. "furlongs per fortnight")
          if unit_match
            per_pos = pos
            if scan(/\s+per\s+/)
              den_match = scan(UNIT_STRING)
              if den_match
                unit_match = "#{unit_match}/#{den_match}"
              else
                self.pos = per_pos
              end
            end
          end

          if unit_match && (unit_match =~ /[\/\*·⋅\^]/ || (Units.known?(unit_match) && !check(/\s*\(/)))
            next_token
            left = BinaryOp.new(left, method, Var.new(unit_match))
          else
            self.pos = saved_pos
            next_token_skip_whitespace
            right = parse_logical_and
            left = BinaryOp.new(left, method, right)
          end
        when :"^"
          check_void_value(left)
          method = @token.type
          next_token_skip_whitespace
          right = parse_logical_and
          left = BinaryOp.new(left, method, right)
        when :".|", :".^"
          # Phase 4e: dot-prefix bitwise-or / bitwise-xor share the
          # logical_or precedence slot with their scalar counterparts.
          check_void_value(left)
          method = @token.type
          next_token_skip_whitespace
          right = parse_logical_and
          left = BinaryOp.new(left, method, right)
        else
          return left
        end
      end
    end

    def parse_unary
      operator = @token.type

      case operator
      when :"!"
        parse_negation
      when :"√"
        # `√expr` ⇒ `expr.sqrt` — mirrors the compiled parser. Recursing
        # through parse_unary keeps superscripts inside: √x² = √(x²).
        next_token
        unexpected "whitespace following unary operator" if @token.whitespace?
        check_void
        Call.new(parse_unary, "sqrt")
      when :+, :-, :~, :"%+", :"%-"
        next_token

        unexpected "whitespace following unary operator" if @token.whitespace?

        check_void

        Call.new(parse_unary, operator.to_s)
      else
        parse_atomic_with_method
      end
    end

    def parse_negation
      next_token
      unexpected "whitespace following bang" if @token.whitespace?
      Not.new parse_unary
    end

    def parse_atomic_with_method
      atomic = parse_atomic

      # Handle: <quantity> of <substance>
      # After parse_atomic, @token is :SP (space after the unit) and scanner pos
      # is past that space, pointing at "of ...". We check @token is :SP and
      # scan "of" + substance words directly from the raw scanner.
      if atomic.is_a?(QuantityLiteral) && @token.type?(:SP)
        saved_pos = pos
        if scan(/of\s+/)
          words = []
          while (word = scan(/[a-z_]+/i))
            words << word
            sp = pos
            unless scan(/\s+/) && check(/[a-z_]/i)
              self.pos = sp
              break
            end
          end
          if words.any?
            next_token # re-sync @token with scanner position
            atomic = Call.new(atomic, "of", [StringLiteral.new(words.join(" "))])
          else
            self.pos = saved_pos
          end
        end
      end

      parse_atomic_method_suffix(atomic)
    end

    def parse_atomic_method_suffix(atomic)
      # @todo lots of body
      while true
        case @token.type
        # + receiver.id(...args)
        #           .sum        ^-- HERE
        when :NL
          case atomic
          when ClassDef, ModuleDef, Def
            # no chaining
            break
          else
            # continue chaining
          end

          if method_continuation_after_newline?
            next_token_skip_whitespace
          else
            break
          end
        when :".", :"&."
          next_token_skip_space
          # :TYPE included so reserved type names double as method names
          # after a dot (`Tensor.bf16`) — the compiled parser accepts this.
          check_for :ID, :NAME, :KEYWORD, :TYPE

          name = @token.value.to_s
          name_file = @token.file
          name_row = @token.row
          name_col = @token.col
          next_token

          args = parse_call_args
          block = parse_block

          atomic = if block
                     Call.new(atomic, name, args || [], block)
                   else
                     args ? Call.new(atomic, name, args) : Call.new(atomic, name)
                   end
          atomic.set_location(name_file, name_row, name_col)
        when :MAP
          # /method     → .map { |__x| __x.method }
          # /method(a)  → .map { |__x| __x.method(a) }
          # /method:op  → .map { |__x| __x.method }.reduce { |__a, __x| __a op __x }
          next_token # consume MAP
          name = @token.value.to_s
          next_token

          args = parse_call_args
          x_var = Var.new("__x")
          body = args ? Call.new(x_var, name, args) : Call.new(x_var, name)
          map_block = Block.new([Arg.new("__x")], body)
          atomic = Call.new(atomic, "map", [], map_block)

          # Check for :reduce suffix
          if @token.type?(:SYMBOL)
            op = AST.intern_name_without_prefix(@token.value, ":")
            next_token
            a_var = Var.new("__a")
            x_var2 = Var.new("__x")
            reduce_body = if VALID_METHOD_NAMES.include?(op.to_sym)
                            BinaryOp.new(a_var, op.to_sym, x_var2)
                          else
                            Call.new(a_var, op, [x_var2])
                          end
            reduce_block = Block.new([Arg.new("__a"), Arg.new("__x")], reduce_body)
            atomic = Call.new(atomic, "reduce", [], reduce_block)
          end
        when :"[]="
          error "expected space after ']', e.g. array[i] = value"
        when :"[]"
          check_void_value(atomic)

          next_token_skip_space

          atomic = Call.new(atomic, "[]")
        when :"["
          # Don't treat [ as indexing after control flow — it's a new array literal
          break if atomic.is_a?(If) || atomic.is_a?(While) || atomic.is_a?(Begin) || atomic.is_a?(Case) || atomic.is_a?(CaseExpr)
          check_void_value(atomic)

          next_token_skip_whitespace

          args = []
          while !@token.type?(:"]")
            args << parse_assignment_no_control
            skip_space
            if @token.type?(:",")
              next_token_skip_whitespace
            else
              skip_whitespace
              check_for_one :"]"
              break
            end
          end

          next_token_skip_space

          atomic = Call.new(atomic, "[]", args)
        when :"++"
          break unless atomic.can_assign?
          next_token
          atomic = AssignOp.new(atomic, :+, Int.new(1))
        when :"--"
          break unless atomic.can_assign?
          next_token
          atomic = AssignOp.new(atomic, :-, Int.new(1))
        when :SUPERSCRIPT
          exp_str = @token.value
          digits = exp_str.chars.map { |c| Tungsten::Units::SUPERSCRIPT_DIGITS[c] || c }.join
          exponent = Int.new(digits.to_i)
          next_token
          atomic = BinaryOp.new(atomic, :**, exponent)
        else
          break
        end
      end

      atomic
    end

    def implicit_each?(node)
      return false unless @token.type?(:"->") || @token.type?(:"{")
      return false if node.is_a?(Def) || node.is_a?(Fn)
      return false if @token.row != node.location_row  # must be same line
      true
    end


    def parse_atomic
      case @token.type
      when :"("
        parse_grouped_expression
      when :"&("
        parse_block_call
      when :"["
        parse_array_literal
      when :"{"
        parse_hash_literal

      when :".", :"&."
        parse_atomic_method_suffix(Var.new("self"))

      when :"[]"
        node_and_next_token ArrayLiteral.new

      when :"::"
        parse_global_path
      when :"->"
        parse_method
      when :LAMBDA_ARITY
        parse_lambda_with_arity

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
        node_and_next_token Nil.new

      when :STRING
        node_and_next_token StringLiteral.new(@token.value)
      when :REGEX
        pattern, options = @token.value
        node_and_next_token RegexLiteral.new(pattern, options)
      when :STRING_INTERP
        parts = @token.value.map do |type, val|
          if type == :str
            StringLiteral.new(val)
          else
            Tungsten::Parser.parse(val)
          end
        end
        node_and_next_token StringInterpolation.new(parts)
      when :CODEPOINT
        node_and_next_token Char.new(@token.value)
      when :CHAR
        node_and_next_token Char.new(@token.value)
      when :CURRENCY
        num_str, prefix, suffix = @token.value
        sym = [prefix, suffix&.delete("/-")].compact.join
        node_and_next_token CurrencyLiteral.new(num_str, sym)
      when :PERCENTAGE
        num_str, num_type = @token.value
        node_and_next_token PercentageLiteral.new(num_str, num_type)
      when :QUANTITY
        node_and_next_token parse_quantity_token
      when :MEASUREMENT
        node_and_next_token parse_measurement_token
      when :MEASURED_QUANTITY
        node_and_next_token parse_measured_quantity_token
      when :DECIMAL
        node_and_next_token Decimal.new(@token.value)
      when :FLOAT
        node_and_next_token Float.new(@token.value)
      when :INT
        node_and_next_token Int.new(@token.value)
      when :WVALUE
        node_and_next_token AST::WValue.new(@token.value)

      when :CIDR6
        node_and_next_token AST::CIDR6.new(@token.value)
      when :CIDR4
        node_and_next_token AST::CIDR4.new(@token.value)
      when :IP6
        node_and_next_token AST::IP6.new(@token.value)
      when :IP4
        node_and_next_token AST::IP4.new(@token.value)

      when :UUID
        node_and_next_token AST::UUID.new(@token.value)

      when :DATETIME
        node_and_next_token AST::DateTime.new(@token.value)
      when :TIME
        node_and_next_token AST::TimeLiteral.new(@token.value)
      when :DATE
        node_and_next_token AST::Date.new(@token.value)
      when :WEEK
        node_and_next_token AST::Week.new(@token.value)
      when :MONTH
        node_and_next_token AST::Month.new(@token.value)
      when :RATIONAL
        node_and_next_token AST::RationalLiteral.new(@token.value)

      when :DURATION
        node_and_next_token AST::Duration.new(@token.value)

      when :COLOR
        v = @token.value
        node_and_next_token AST::ColorLiteral.new(v[0], v[1], v[2], v[3])

      when :KEY
        node_and_next_token KeyLiteral.new(@token.value)

      when :BYTE_ARRAY
        node_and_next_token ByteArrayLiteral.new(@token.value)
      when :BYTE_ARRAY_INTERP
        parts = @token.value.map do |type, val|
          if type == :bytes
            ByteArrayLiteral.new(val)
          else
            Tungsten::Parser.parse(val)
          end
        end
        node_and_next_token ByteArrayInterpolation.new(parts)

      when :IVAR
        node_and_next_token InstanceVar.new(@token.value.to_s)
      when :REGEX_CAPTURE
        node_and_next_token GlobalVar.new("$#{@token.value}")
      when :PARG
        node_and_next_token Var.new("__arg#{@token.value.to_s.delete_prefix("@")}")
      when :CVAR
        node_and_next_token ClassVar.new(@token.value.to_s)
      when :CONSTANT
        parse_var_or_call
      when :GLOBAL
        node_and_next_token GlobalVar.new(@token.value.to_s)
      when :UNDERSCORE

      when :"$~", :"$?"
      when :MAGIC_INDEX # $[0-9]
      when :MAGIC_LINE
        node_and_next_token MagicConstant.new(:__LINE__)
      when :MAGIC_FILE
        node_and_next_token MagicConstant.new(:__FILE__)
      when :MAGIC_DIR
        node_and_next_token MagicConstant.new(:__DIR__)

      when :CLASS
        parse_class

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
        when :continue
          parse_continue
        when :fn
          parse_fn
        when :if
          parse_if
        when :in
          parse_in
        when :loop
          parse_loop_forever
        when :is
          parse_is
        when :trait
          parse_trait
        when :load
          parse_load
        when :method
          parse_method
        when :module
          parse_module
        when :next
          parse_next
        when :on
          parse_on_guard
        when :raise
          parse_raise
        when :return
          parse_return
        when :super
          parse_super
        when :unless
          parse_unless
        when :use
          parse_use
        when :until
          parse_loop Until
        when :while
          parse_loop While
        when :when
          parse_when_chain
        when :with
          if with_loop_start?
            parse_with
          else
            node_and_next_token Var.new(@token.value.to_s)
          end
        when :yield
          parse_yield
        else
          unexpected
        end

      when :TYPE
        type_name = @token.value
        next_token
        if @token.type?(:"[")
          # Typed array: i128[1000]
          next_token_skip_whitespace
          size = parse_assignment_no_control
          check_for :"]"
          next_token
          TypedArray.new(type_name, size)
        else
          # Bare type name as value
          Var.new(type_name)
        end

      when :ID
        parse_var_or_call
      when :NAME
        parse_var_or_call

      when :"<<"
        next_token_skip_whitespace
        Print.new([parse_assignment])
      when :"<!"
        next_token_skip_whitespace
        Raise.new(parse_assignment)
      when :"<-"
        next_token_skip_whitespace
        Write.new([parse_assignment])

      when :DEDENT
        # do nothing

      else
        unexpected
      end
    end

    def parse_array_literal
      list = []

      open("array literal") do
        next_token_skip_whitespace_all

        while !@token.type?(:"]")
          exp = if @token.type?(:"*")
                  next_token_skip_whitespace_all
                  Splat.new(parse_assignment_no_control)
                else
                  parse_assignment_no_control
                end

          list << exp

          skip_whitespace_all

          if @token.type?(:",")
            next_token_skip_whitespace_all
          else
            skip_whitespace_all
            check_for :"]"
            break
          end
        end

        next_token_skip_space
      end

      ArrayLiteral.new(list)
    end

    def parse_begin
      loc_file = @token.file
      loc_row = @token.row
      loc_col = @token.col
      next_token
      skip_statement_end

      body = with_indent { parse_body }

      rescue_var = nil
      rescue_body = nil
      if @token.keyword?(:rescue)
        next_token_skip_space
        if @token.type?(:ID)
          rescue_var = @token.value.to_s
          next_token
          # Typed rescue: rescue e : ErrorType — discard type for now
          skip_space
          if @token.type?(:":")
            next_token_skip_space
            check_for :NAME, :CONSTANT
            next_token
          end
        end
        skip_statement_end
        rescue_body = with_indent { parse_body }
      end

      ensure_body = nil
      if @token.keyword?(:ensure) || @token.keyword?(:always)
        next_token
        skip_statement_end
        ensure_body = with_indent { parse_body }
      end

      node = Begin.new(body, rescue_var, rescue_body, ensure_body)
      node.set_location(loc_file, loc_row, loc_col)
      node
    end

    def parse_raise
      loc_file = @token.file
      loc_row = @token.row
      loc_col = @token.col
      next_token_skip_space
      value = parse_assignment_no_control
      node = Raise.new(value)
      node.set_location(loc_file, loc_row, loc_col)
      node
    end

    def parse_exception_handler(body)
      body
    end

    def parse_continue = parse_next

    def parse_alias
      next_token_skip_space
      check_for :ID, :SYMBOL
      new_name = @token.value.to_s
      next_token_skip_space
      check_for :ID, :SYMBOL
      old_name = @token.value.to_s
      next_token
      Alias.new(new_name, old_name)
    end
    def parse_in
      loc_file = @token.file
      loc_row = @token.row
      loc_col = @token.col
      next_token_skip_space
      # Parse colon-separated namespace path: in Tungsten:Forge:H2
      # Lexer tokenizes "Tungsten:Forge:H2" as NAME("Tungsten") SYMBOL(":Forge") SYMBOL(":H2")
      check_for :NAME
      parts = [@token.value.to_s]
      next_token
      while @token.type?(:SYMBOL) && @token.value.to_s.match?(/\A:[A-Z]/)
        parts << AST.intern_name_without_prefix(@token.value, ":")
        next_token
      end
      @namespace_prefix = AST.intern_name(parts.join(":"))

      node = Nil.new
      node.set_location(loc_file, loc_row, loc_col)
      node
    end
    def parse_is
      next_token_skip_space
      check_for :NAME
      name = @token.value
      next_token
      Is.new(name)
    end

    def parse_trait
      loc_file = @token.file
      loc_row = @token.row
      loc_col = @token.col
      next_token_skip_whitespace
      check_for :NAME
      name = @token.value
      next_token
      skip_statement_end

      if @token.type?(:INDENT)
        previous_in_class_body = @in_class_body
        @in_class_body = true
        begin
          body = with_indent { parse_body }
        ensure
          @in_class_body = previous_in_class_body
        end
      else
        body = List.new
      end

      node = TraitDef.new(name, body)
      node.set_location(loc_file, loc_row, loc_col)
      node
    end
    def parse_load      = unexpected "load not yet implemented"
    def parse_use
      loc_file = @token.file
      loc_row = @token.row
      loc_col = @token.col

      # Scan the path directly from source as raw text.
      # Supports: use argon, use hammer/connection, use tungsten-hammer, use "path"
      skip(/[ \t]+/)
      if check(/"/)
        next_token_skip_space
        path = @token.value
        next_token
      else
        path = scan(/[^\s;#]+/).to_s
        next_token
      end

      node = Use.new(path)
      node.set_location(loc_file, loc_row, loc_col)
      node
    end
    def parse_with
      loc_file = @token.file
      loc_row = @token.row
      loc_col = @token.col
      next_token_skip_whitespace
      bindings = []

      loop do
        check_for :ID, :NAME
        var = Var.new(@token.value.to_s)
        next_token_skip_whitespace

        unless @token.keyword?(:in)
          unexpected "expecting 'in'"
        end
        next_token_skip_whitespace

        expr = parse_assignment_no_control
        bindings << [var, expr]

        break unless @token.type?(:",")
        next_token_skip_whitespace
      end

      skip_statement_end
      body = with_indent { parse_body }
      node = With.new(bindings, body)
      node.set_location(loc_file, loc_row, loc_col)
      node
    end
    # -- Platform guard blocks --
    #
    #   on macos
    #     -> clock_ms; ...
    #
    #   on linux && x86_64 with io_uring
    #     -> submit(...); ...
    #
    # Grammar:
    #   target_guard   := target_or (with_clause)*
    #   target_or      := target_and ('||' target_and)*
    #   target_and     := target_not ('&&' target_not)*
    #   target_not     := '!' target_not | target_primary
    #   target_primary := IDENT | '(' target_or ')'
    #   with_clause    := 'with' IDENT
    #
    def parse_on_guard
      loc_file = @token.file
      loc_row = @token.row
      loc_col = @token.col
      next_token_skip_space

      predicate = parse_target_or
      capabilities = []
      while @token.keyword?(:with)
        next_token_skip_space
        check_for :ID, :NAME
        capabilities << @token.value.to_s
        next_token_skip_space
      end

      skip_statement_end
      body = with_indent { parse_body }

      node = OnGuard.new(predicate, capabilities, body)
      node.set_location(loc_file, loc_row, loc_col)
      node
    end

    def parse_target_or
      left = parse_target_and
      while @token.type?(:"||")
        next_token_skip_space
        left = TargetOr.new(left, parse_target_and)
      end
      left
    end

    def parse_target_and
      left = parse_target_not
      while @token.type?(:"&&")
        next_token_skip_space
        left = TargetAnd.new(left, parse_target_not)
      end
      left
    end

    def parse_target_not
      if @token.type?(:"!")
        next_token_skip_space
        TargetNot.new(parse_target_not)
      else
        parse_target_primary
      end
    end

    def parse_target_primary
      if @token.type?(:"(")
        next_token_skip_space
        expr = parse_target_or
        consume :")"
        skip_space
        expr
      else
        check_for :ID, :NAME
        name = @token.value.to_s
        next_token_skip_space
        TargetDesignator.new(name)
      end
    end

    def parse_global_path
      next_token
      check_for :NAME, :CONSTANT
      names = [@token.value.to_s]
      next_token
      while @token.type?(:"::")
        next_token
        check_for :NAME, :CONSTANT
        names << @token.value.to_s
        next_token
      end
      Path.global(names)
    end

    def parse_word_array
      words = scan_word_array_body
      ArrayLiteral.new(words.map { |w| StringLiteral.new(w) })
    end

    def parse_symbol_array
      words = scan_word_array_body
      ArrayLiteral.new(words.map { |w| Symbol.new(w) })
    end

    def scan_word_array_body
      words = []
      scan(/\s*/)
      until scan(/\]/)
        error "unterminated word array" if eos?
        if scan(/#[^\n]*/)
          scan(/\s*/)
          next
        end
        word = scan(/[^\s\]#]+/)
        error "unexpected token in word array" unless word
        words << word
        scan(/\s*/)
      end
      next_token
      words
    end

    def parse_case
      loc_file = @token.file
      loc_row = @token.row
      loc_col = @token.col
      next_token_skip_space

      # Condition-less case: `case` followed by newline, each `when` is a boolean guard
      conditionless = @token.type?(:NL) || @token.type?(:";")

      receiver = conditionless ? nil : parse_assignment_no_control
      skip_statement_end

      whens = []
      else_body = nil

      case_arrow_stop = -> {
        @token.type?(:DEDENT) || @token.type?(:EOF) || @token.type?(:")") ||
          @token.type?(:"]") || @token.type?(:"}") || @token.type?(:",")
      }

      parse_arrow_clauses = -> do
        until case_arrow_stop.call
          skip_statement_end
          break if case_arrow_stop.call

          if @token.type?(:"=>")
            # Catch-all: => body
            next_token_skip_space
            else_body = parse_arrow_case_body
          else
            conditions = [parse_expression]
            while @token.comma?
              next_token_skip_whitespace
              conditions << parse_expression
            end
            skip_space
            consume :"=>"
            skip_space
            body = parse_arrow_case_body
            whens << [conditions, body]
          end
        end
      end

      if @token.keyword?(:when)
        # when clauses are at the same indent level as case
        whens, else_body = parse_when_clauses
      elsif conditionless
        parse_arrow_clauses.call
      elsif !conditionless && @token.type?(:INDENT)
        # Arrow-style clauses are indented
        with_indent do
          if @token.keyword?(:when)
            whens, else_body = parse_when_clauses
          else
            parse_arrow_clauses.call
          end
        end
      else
        parse_arrow_clauses.call
      end

      node = CaseExpr.new(receiver, whens, else_body)
      node.set_location(loc_file, loc_row, loc_col)
      node
    end

    def parse_when_chain
      loc_file = @token.file
      loc_row = @token.row
      loc_col = @token.col
      whens, else_body = parse_when_clauses
      node = CaseExpr.new(nil, whens, else_body)
      node.set_location(loc_file, loc_row, loc_col)
      node
    end

    def parse_when_clauses
      whens = []
      else_body = nil

      skip_statement_end

      while @token.keyword?(:when)
        next_token_skip_space

        conditions = [parse_assignment_no_control]
        while @token.comma?
          next_token_skip_whitespace
          conditions << parse_assignment_no_control
        end

        whens << [conditions, parse_when_clause_body]
        skip_statement_end
      end

      if @token.keyword?(:else)
        next_token
        else_body = parse_when_clause_body
      end

      [whens, else_body]
    end

    def parse_when_clause_body
      if @token.keyword?(:then)
        next_token_skip_space
        # `when X then return/break/next ...` is a statement position; the
        # newline body form (parse_body, below) already allows control flow,
        # so the inline `then` form must too. Only route the control keywords
        # through parse_assignment (which skips the check_void guard) — every
        # other body keeps parse_assignment_no_control unchanged.
        if @token.keyword?(:return) || @token.keyword?(:break) || @token.keyword?(:next)
          return parse_assignment
        end
        return parse_assignment_no_control
      elsif @token.type?(:NL) || @token.type?(:";")
        skip_statement_end
        with_indent { parse_body }
      else
        skip_space
        parse_assignment_no_control
      end
    end

    def parse_arrow_case_body
      if @token.type?(:NL) || @token.type?(:";")
        skip_whitespace
        if @token.type?(:INDENT)
          with_indent { parse_body }
        else
          Nil.new
        end
      else
        body = [parse_assignment_no_control]
        while @token.type?(:";")
          next_token_skip_space
          break if @token.type?(:NL) || @token.type?(:EOF) || @token.type?(:DEDENT) ||
                   @token.type?(:")") || @token.type?(:"]") || @token.type?(:"}") || @token.type?(:",")

          body << parse_assignment_no_control
        end
        body.length == 1 ? body.first : List.from(body)
      end
    end

    def parse_hash_literal
      entries = []

      open("hash literal") do
        next_token_skip_whitespace_all

        while !@token.type?(:"}")
          # symbol-style key: name: value
          if keyword_label_token?
            key_name = @token.value.to_s
            key = StringLiteral.new(key_name)
            next_token  # past label
            next_token_skip_whitespace_all  # past :
            # Shorthand: {name:} or {name:, ...} → {name: name}
            if @token.type?(:",") || @token.type?(:"}")
              value = Var.new(key_name)
              entries << [key, value]
              skip_whitespace_all
              if @token.type?(:",")
                next_token_skip_whitespace_all
              else
                check_for :"}"
              end
              next
            end
          else
            key = parse_assignment_no_control
            skip_whitespace_all
            if @token.type?(:"=>")
              next_token
              skip_whitespace_all
            elsif @token.type?(:",") || @token.type?(:"}")
              # Set literal: `{1, 2, 3}` or `{1}` — bare elements separated by commas.
              # First element already parsed into `key`.
              return parse_set_literal_after_first(key)
            else
              consume :":"
              skip_whitespace_all
            end
          end

          value = parse_assignment_no_control
          entries << [key, value]

          skip_whitespace_all

          if @token.type?(:",")
            next_token_skip_whitespace_all
          else
            skip_whitespace_all
            check_for :"}"
            break
          end
        end

        next_token_skip_space
      end

      HashLiteral.new(entries)
    end

    # Continues parsing a set literal after the first element has been consumed.
    # Caller passed `first` as the parsed first element; the parser is currently
    # at `,` or `}`.
    def parse_set_literal_after_first(first)
      elements = [first]
      while @token.type?(:",")
        next_token_skip_whitespace_all
        break if @token.type?(:"}")  # trailing comma
        elements << parse_assignment_no_control
        skip_whitespace_all
      end
      check_for :"}"
      next_token_skip_space
      AST::SetLiteral.new(elements)
    end

    def parse_super
      next_token
      args = parse_call_args
      Super.new(args || [])
    end

    def parse_module
      loc_file = @token.file
      loc_row = @token.row
      loc_col = @token.col
      next_token_skip_whitespace

      check_for :NAME
      name = @token.value
      next_token
      name = AST.intern_name("#{@namespace_prefix}:#{name}") if @namespace_prefix && !name.to_s.include?(":")

      skip_statement_end

      if @token.type?(:INDENT)
        body = with_indent { parse_body }
      else
        body = List.new
      end

      node = ModuleDef.new(name, body)
      node.set_location(loc_file, loc_row, loc_col)
      node
    end

    def parse_class
      loc_file = @token.file
      loc_row = @token.row
      loc_col = @token.col
      next_token_skip_whitespace

      check_for :NAME, :CONSTANT, :ID, :TYPE

      name = @token.value
      next_token_skip_space

      # Namespace path: + Argon:Result (e.g., Module:NestedClass)
      if @token.type?(:SYMBOL) && @token.value.to_s.match?(/\A:[A-Z]/)
        while @token.type?(:SYMBOL) && @token.value.to_s.match?(/\A:[A-Z]/)
          name = AST.intern_name("#{name}:#{AST.intern_name_without_prefix(@token.value, ":")}")
          next_token_skip_space
        end
      end
      name = AST.intern_name("#{@namespace_prefix}:#{name}") if @namespace_prefix && !name.to_s.include?(":")

      superclass = nil
      class_role = nil

      # A class role annotation `[role]` (e.g. `[slab]`) may appear either
      # before the superclass (`+ Foo [slab]`) or after it
      # (`+ File < Node [slab]`); both forms occur in the compiler sources.
      parse_class_role = lambda do
        next_token_skip_space
        check_for :NAME, :CONSTANT, :ID, :TYPE
        class_role = @token.value
        next_token_skip_space
        check_for(:"]")
        next_token_skip_space
      end

      parse_class_role.call if @token.type?(:"[")

      if @token.type?(:"<")
        next_token_skip_space
        check_for :NAME, :CONSTANT, :ID, :TYPE
        superclass = @token.value
        next_token_skip_space
      end

      parse_class_role.call if @token.type?(:"[") && class_role.nil?

      skip_statement_end

      previous_in_class_body = @in_class_body
      @in_class_body = true
      begin
        if @token.type?(:INDENT)
          body = with_indent { parse_body }
        else
          body = List.new
        end
      ensure
        @in_class_body = previous_in_class_body
      end

      node = ClassDef.new(name, body, superclass, class_role: class_role)
      node.set_location(loc_file, loc_row, loc_col)
      node
    end

    def parse_data_declaration
      next_token_skip_space
      return Nil.new unless @token.type?(:ID) || @token.type?(:TYPE)

      kind = @token.value.to_s
      next_token_skip_space
      if @token.type?(:"(")
        next_token_skip_space
        check_for :NAME, :CONSTANT, :ID, :TYPE
        next_token_skip_space
        check_for :")"
        next_token_skip_space
      end
      skip_statement_end

      return Nil.new unless @token.type?(:INDENT)

      fields = []
      line = []
      flush_line = lambda do
        if kind == "data" && !line.empty?
          if line[0] == "field" && line[1]
            fields << line[1]
          end
        end
        line = []
      end

      depth = 0
      loop do
        case @token.type
        when :INDENT
          depth += 1
        when :DEDENT
          flush_line.call
          depth -= 1
          next_token
          break if depth <= 0
          next
        when :NL
          flush_line.call if depth > 0
        else
          line << @token.value.to_s if depth > 0 && @token.respond_to?(:value) && @token.value
        end

        next_token
      end

      if kind == "data" && !fields.empty?
        return Call.new(nil, "ro", fields.uniq.map { |field| Symbol.new(field) })
      end

      Nil.new
    end

    def parse_method
      parse_method_reset

      method = with_isolated_scope do
        parse_method_internal
      end

      parse_method_reset

      method
    end

    def parse_fn
      parse_method_reset

      method = with_isolated_scope do
        parse_method_internal(node_class: Fn)
      end

      parse_method_reset

      method
    end

    def parse_lambda_with_arity
      parse_method_reset

      method = with_isolated_scope do
        @nested_methods += 1

        # Extract arity from "->/2"
        arity = @token.value[3..].to_i

        next_token

        generate_positional_args(arity)

        skip_space

        body = case @token.type
               when :NL, :";"
                 skip_whitespace
                 @token.type?(:INDENT) ? with_indent { parse_body } : Nil.new
               else
                 parse_assignment_no_control
               end

        @nested_methods -= 1

        Def.new(nil, @method[:args].any? ? @method[:args] : nil, body)
      end

      parse_method_reset

      method
    end

    def parse_method_reset
      @method[:block]        = false
      @method[:initialize]   = false
      @method[:super]        = false
      @method[:default]      = false

      @method[:args]         = []
      @method[:assigns]      = []

      @method[:splat]        = nil
      @method[:splat_index]  = nil
      @method[:double_splat] = nil
      @method[:block_name]   = nil
    end

    # -> name(args)       named method with parenthesized args
    # -> name/2           named method with arity (positional @1, @2)
    # -> name/2 @1 + @2   named method with arity, inline body
    # -> (a, b) a + b     anonymous lambda
    # fn name(args)       pure function (auto-memoized, no self)
    # fn name/2           pure function with arity
    def parse_method_internal(node_class: Def)
      @nested_methods += 1
      loc_file = @token.file
      loc_row = @token.row
      loc_col = @token.col

      # Consume the declaration token: -> or fn
      if node_class == Fn
        next_token  # consume KEYWORD(:fn)
      else
        consume :"->"
      end

      # Space is optional before ( for anonymous lambdas: ->(x) body
      if @token.type?(:SP)
        next_token
      elsif !@token.type?(:"(")
        error "expected space or '(' after '->'"
      end

      # Anonymous lambda: -> (a, b) body
      if @token.type?(:"(")
        return parse_anonymous_lambda(node_class:)
      end

      # .method class method definitions (dot-prefix syntax)
      receiver = nil
      if @token.type?(:".")
        receiver = Var.new("self")
        next_token  # consume "."
      elsif @token.type?(:ID) && @token.value == "self" && check(/\./)
        error "use '-> .method_name' for class methods (not '-> self.method_name')"
      end

      name = parse_method_name
      arity = extract_arity(name)
      base_name = arity ? name.to_s.split("/", 2)[0] : name

      next_token

      trailing_expr = nil
      inline_body = false

      case @token.type

      # -> name
      when :NL, :";"
        # no args, no inline body

      # -> name/2 @1 + @2
      when :SP, :"&"
        if arity
          next_token  # consume SP, inline body follows
          inline_body = true
        else
          unexpected "use parentheses when a method has parameters"
        end

      # -> name(args)
      when :"("
        if arity
          error "arity methods cannot have parenthesized parameters"
        end

        # don't skip nl, looks ugly to start arguments on next line
        next_token_skip_space
        parse_method_args
        consume :")"

        if base_name.to_s.end_with?("=")
          if base_name != "[]=" && (@method[:args].size > 1 || @method[:splat] || @method[:double_splat])
            error "setter method '#{base_name}' has arity > 1"
          elsif @method[:block]
            error "setter method '#{base_name}' has a block"
          end
        end

        # Check for trailing expression after ): -> name(args) expr
        if @token.type?(:SP)
          next_token
          inline_body = true
        end
      else
        unexpected
      end

      # Phase 3 annotations: optional `(i64 i64)` param types and bare
      # return type after the param list. Sync with compiler-side
      # parser.w's looks_like_param_types? / looks_like_return_type?.
      # See CLAUDE.md dual-parser-sync rule.
      param_types = nil
      return_type = nil
      if inline_body || @token.type?(:SP)
        # Bring us to the first non-space token after the arg list.
        skip_space if @token.type?(:SP)

        # Param types: `(TYPE TYPE ...)` where contents are only :TYPE
        # tokens and spaces, terminated by `)`.
        if @token.type?(:"(") && looks_like_param_types_ahead?
          next_token_skip_space
          param_types = []
          while !@token.type?(:")")
            unless @token.type?(:TYPE)
              error "expected type name in param type list, got #{@token.type}"
            end
            param_types << @token.value.to_sym
            next_token_skip_space
          end
          consume :")"
          skip_space
        end

        # Return type: bare :TYPE followed by `:` (inline body) or
        # newline/indent/statement-end.
        if @token.type?(:TYPE) && looks_like_return_type_ahead?
          return_type = @token.value.to_sym
          next_token
          skip_space
        end

        # Phase 3 inline body introducer: `:` after annotations.
        if @token.type?(:":")
          next_token_skip_space
          inline_body = true
        end
      end

      # Generate positional args for arity methods, or set block param for /&
      if arity == :block
        @method[:block] = Arg.new("&")
      elsif arity
        generate_positional_args(arity)
      end

      # Parse trailing expression — could be inline body or accumulator
      if inline_body
        if @token.type?(:"=")
          next_token_skip_space
        end
        trailing_expr = parse_assignment_no_control
      end

      # Snapshot args before body parsing — nested method defs reset @method
      args         = @method[:args].any? ? @method[:args] : nil
      assigns      = @method[:assigns]
      block        = @method[:block]
      splat_index  = @method[:splat_index]
      double_splat = @method[:double_splat]

      if trailing_expr
        skip_space

        if @token.type?(:NL) || @token.type?(:";")
          skip_whitespace

          if @token.type?(:INDENT)
            # Trailing expr + indented body = accumulator
            body = with_indent { parse_body }

            if assigns.size > 0
              exps = assigns.dup
              exps.concat(body.is_a?(List) ? body.list : [body])
              body = List.from(exps)
              body = parse_exception_handler(body)
            end

            if trailing_expr.is_a?(Assign) && trailing_expr.name.is_a?(Var)
              acc_name = trailing_expr.name.name.to_s
              init_expr = trailing_expr.value
            else
              # Determine accumulator name: first use of "out" or "acc" in body
              acc_name = detect_accumulator_name(body)
              acc_name ||= "out"
              init_expr = trailing_expr
            end

            init = Assign.new(Var.new(acc_name), init_expr)
            ret  = Var.new(acc_name)
            exps = [init]
            exps.concat(body.is_a?(List) ? body.list : [body])
            exps.push(ret)
            body = List.from(exps)
          else
            # Trailing expr, no indented body = inline body
            body = trailing_expr
            body = List.from(assigns + [body]) if assigns.size > 0
          end
        else
          # Trailing expr, same line continues = inline body
          body = trailing_expr
          body = List.from(assigns + [body]) if assigns.size > 0
        end
      else
        skip_space

        case @token.type
        when :NL, :";"
          skip_whitespace

          if @token.type?(:INDENT)
            body = with_indent { parse_body }

            if assigns.size > 0
              exps = []
              exps.concat assigns

              if body.is_a?(List)
                exps.concat(body.list)
              else
                exps.push(body)
              end

              body = List.from(exps)

              body = parse_exception_handler(body)
            end
          else
            body = List.from(assigns)
          end
        else
          # Inline body: -> name(args) expression
          body = parse_assignment_no_control
          body = List.from(assigns + [body]) if assigns.size > 0
        end
      end

      # Fallthrough: `: expr` after body — default return value
      skip_space
      if @token.type?(:":")
        next_token_skip_space
        fallthrough = parse_assignment_no_control
        exps = body.is_a?(List) ? body.list.dup : (body ? [body] : [])
        exps.push(fallthrough)
        body = List.from(exps)
      end

      @nested_methods -= 1

      node = node_class.new(base_name, args, body)
      node.receiver     = receiver
      node.block        = block
      node.splat_index  = splat_index
      node.double_splat = double_splat
      node.param_types  = param_types
      node.return_type  = return_type
      node.set_location(loc_file, loc_row, loc_col)

      node
    end

    # Phase 3 lookahead: when @token is at `:"("` and the paren group
    # contains only space-separated type names (no identifiers, commas,
    # or operators), it's a param-type annotation. Sync with the
    # compiler's parser.w looks_like_param_types? helper.
    def looks_like_param_types_ahead?
      saved_pos = pos
      # The scanner has already consumed the `(` token's text, so pos
      # is at the content inside the paren group.
      result = !!scan(/\A\s*(?:#{Tungsten::Lexer::TYPE_NAME_PATTERN})(?:\s+(?:#{Tungsten::Lexer::TYPE_NAME_PATTERN}))*\s*\)/)
      self.pos = saved_pos
      result
    end

    # Phase 3 lookahead: when @token is at `:TYPE`, is the token a
    # return-type annotation? True iff what comes after it (modulo
    # trailing whitespace) is `:` (inline body), a newline, `;`, or EOF.
    # Rejects `type.method`, `type[idx]`, `type(args)` expression starts.
    def looks_like_return_type_ahead?
      saved_pos = pos
      scan(/[ \t]*/)
      ch = rest[0]
      result = ch == ":" || ch == "\n" || ch == ";" || ch.nil?
      self.pos = saved_pos
      result
    end

    # -> (a, b) a + b    anonymous lambda with named args
    # -> (a, b)          anonymous lambda with block body
    #   a + b
    def parse_anonymous_lambda(node_class: Def)
      next_token_skip_space
      parse_method_args
      consume :")"

      skip_space

      body = case @token.type
             when :NL, :";"
               skip_whitespace
               @token.type?(:INDENT) ? with_indent { parse_body } : Nil.new
             else
               parse_assignment_no_control
             end

      @nested_methods -= 1

      node = node_class.new(nil, @method[:args].any? ? @method[:args] : nil, body)
      node.block        = @method[:block]
      node.splat_index  = @method[:splat_index]
      node.double_splat = @method[:double_splat]

      node
    end

    def extract_arity(name)
      return nil unless name.to_s.include?("/")

      suffix = name.to_s.split("/", 2)[1]
      return :block if suffix == "&"

      suffix.to_i
    end

    # Scan AST for first use of "out" or "acc" as a variable name.
    # Returns the name that was found, or nil if neither is used.
    def detect_accumulator_name(node)
      return nil unless node

      case node
      when Var
        return node.name if node.name == "out" || node.name == "acc"
      when List
        node.each do |child|
          result = detect_accumulator_name(child)
          return result if result
        end
      else
        %i[body obj value left right block name].each do |attr|
          next unless node.respond_to?(attr)
          child = node.send(attr)
          next unless child
          next if child.is_a?(String) || child.is_a?(Symbol)

          result = detect_accumulator_name(child)
          return result if result
        end
        if node.respond_to?(:args) && node.args.is_a?(Array)
          node.args.each do |child|
            result = detect_accumulator_name(child)
            return result if result
          end
        end
      end
      nil
    end

    def generate_positional_args(arity)
      (1..arity).each do |i|
        arg = Arg.new("__arg#{i}")
        push_var(arg)
        @method[:args] << arg
      end
    end

    def parse_method_args
      index = 0

      until @token.type?(:")")
        arg = parse_method_arg
        @method[:args] << arg if arg

        @method[:splat_index] = index if @method[:splat_index].nil? && @method[:splat]

        if @token.comma?
          next_token_skip_space
        else
          skip_space
          check_for :")"
        end

        index += 1
      end

      @method[:args]
    end

    def parse_method_arg
      if @token.type?(:"&")
        error "multiple block args defined" if @method[:block_name]
        next_token
        block_arg = parse_block_arg

        conflict = @method[:args].any? { |name| name == block_arg.name }

        if conflict || @method[:double_splat] == block_arg.name
          error "duplicated argument name: #{block_arg.name}"
        end

        return
      end

      if @method[:double_splat]
        error "only block arg allowed after double splat"
      end

      splat = double_splat = false

      case @token.type
      when :"*"
        unexpected "multiple splat args" if @method[:splat]

        next_token
        unexpected unless identifier_name_token?
        splat = true
      when :"**"
        next_token
        unexpected unless identifier_name_token?
        double_splat = true
      end

      ivar_bound = @token.type?(:IVAR)
      name = parse_arg_name

      error "duplicate arg name: #{name}" if @method[:args].any? { |arg| arg.name == name }

      keyword = false
      default = nil

      # Keyword parameter: name: or name: default_value
      if @token.type?(:":")
        error "keyword with splat"        if splat
        error "keyword with double splat" if double_splat
        keyword = true
        next_token_skip_space

        # Check for default value (not , or ) means there's a default)
        unless @token.type?(:",") || @token.type?(:")")
          default = parse_assignment
          skip_space
        end
      elsif @token.type?(:"=")
        error "default with splat"        if splat
        error "default with double splat" if double_splat

        next_token_skip_space

        case @token.type
        when :MAGIC
          default = MagicConstant.new(@token.type)
        else
          default = parse_assignment
        end

        skip_space
      else
        if @method[:default] && !splat && !double_splat && !@method[:has_keyword]
          error "required param after optional"
        end
      end

      error "BUG: name is required" unless name

      @method[:splat]        = name if splat
      @method[:double_splat] = name if double_splat
      @method[:default]      = true if default || keyword
      @method[:has_keyword]  = true if keyword

      arg = Arg.new(name, default)
      arg.keyword = true if keyword
      arg.ivar = true if ivar_bound
      push_var(arg)
    end

    # &block
    def parse_block_arg
      case @token.type
      when :ID, :TYPE, :KEYWORD
        name = parse_arg_name
      when :")", :",", :NL, :EOF
        name = "&"
      else
        unexpected "must name block args"
      end

      block = Arg.new(name)

      push_var(block) unless name == "&"

      @method[:block] = block
    end

    def parse_method_name
      check_for(*VALID_METHOD_NAMES)

      case @token.type
      when :ID_WITH_ARITY
        check_valid_method_name

        @token.value
      when :ID, :TYPE
        check_valid_method_name

        @token.value
      when :KEYWORD
        @token.value.to_s
      else
        # operator
        @token.type.to_s
      end
    end

    def soft_identifier_keyword?
      @token.type?(:KEYWORD) && SOFT_IDENTIFIER_KEYWORDS.include?(@token.value)
    end

    def identifier_name_token?
      @token.type?(:ID) || @token.type?(:TYPE) || soft_identifier_keyword?
    end

    def label_colon_ahead?
      return false unless source_byte_at(pos) == 58

      next_byte = source_byte_at(pos + 1)
      next_byte != 61 && !uppercase_byte?(next_byte)
    end

    def keyword_label_token?
      (@token.type?(:ID) || soft_identifier_keyword?) && label_colon_ahead?
    end

    def named_label_token?
      (@token.type?(:NAME) || @token.type?(:CONSTANT)) && label_colon_ahead?
    end

    def with_loop_start?
      @token.keyword?(:with) && check(/[ \t]+\S+[ \t]+in\b/)
    end

    def method_continuation_after_newline?
      i = skip_raw_whitespace(pos)
      return true if method_continuation_start_at?(i)
      return false unless source_byte_at(i) == 35 && raw_whitespace_byte?(source_byte_at(i + 1))

      i += 2
      i += 1 while (b = source_byte_at(i)) && b != 10
      return false unless source_byte_at(i) == 10

      method_continuation_start_at?(skip_raw_whitespace(i + 1))
    end

    def method_continuation_start_at?(index)
      b = source_byte_at(index)
      return true if b == 38 && source_byte_at(index + 1) == 46

      b == 46 && source_byte_at(index + 1) != 46
    end

    def skip_raw_whitespace(index)
      index += 1 while raw_whitespace_byte?(source_byte_at(index))
      index
    end

    def raw_whitespace_byte?(byte)
      byte == 32 || byte == 9 || byte == 10 || byte == 13 || byte == 12
    end

    def uppercase_byte?(byte)
      byte && byte >= 65 && byte <= 90
    end

    def source_byte_at(index)
      string.getbyte(index)
    end

    # consumes arg name and following whitespace
    def parse_arg_name
      case @token.type
      when :KEYWORD
        error "can't use '#{@token.value}' as an argument name" unless soft_identifier_keyword?

        name = @token.value.to_s
      when :ID, :TYPE
        name = @token.value.to_s
      when :IVAR
        name = @token.value.to_s[1..-1]

        ivar = InstanceVar.new(@token.value.to_s)
        var  = Var.new(name)
        assign = Assign.new(ivar, var)

        @method[:assigns].push assign
      when :CVAR
        unexpected
      else
        unexpected
      end

      next_token
      skip_whitespace

      name
    end

    def parse_grouped_expression
      next_token_skip_whitespace

      first = parse_expression

      if @token.type?(:",")
        elements = [first]
        while @token.type?(:",")
          next_token_skip_whitespace
          elements << parse_expression
        end
        consume :")"
        skip_space
        Tuple.new(elements)
      else
        consume :")"
        skip_space
        first
      end
    end

    def parse_var_or_call
      name = @token.value
      loc_file = @token.file
      loc_row = @token.row
      loc_col = @token.col

      # Prime notation: `x'` is the same-named property on the first
      # argument — `x - x'` reads "my x minus their x". Desugars to
      # `@1.x` (__arg1.x), mirroring the compiled parser; meaningful
      # inside `-> name/N` arity methods.
      if name.to_s.end_with?("'")
        base = name.to_s.delete_suffix("'")
        next_token
        node = Call.new(Var.new("__arg1"), base)
        node.set_location(loc_file, loc_row, loc_col)
        return node
      end

      @last_call_parens = false
      next_token

      # Namespace path: Name:Constant (e.g., Forge:Server, Frame:INTERNAL_ERROR)
      if @token.type?(:SYMBOL) && @token.value.to_s.match?(/\A:[A-Z]/)
        path_names = [name.to_s]
        while @token.type?(:SYMBOL) && @token.value.to_s.match?(/\A:[A-Z]/)
          path_names << AST.intern_name_without_prefix(@token.value, ":")
          next_token
        end
        node = Path.new(path_names)
        node.set_location(loc_file, loc_row, loc_col)
        return node
      end

      args  = parse_call_args
      # Don't consume -> block for known variables — let implicit_each? handle it
      is_var = @scopes.last.include?(name.to_s)
      default = nil
      block = nil
      if %w[ro rw].include?(name.to_s) && @token.type?(:"{")
        if looks_like_hash?
          default = parse_hash_literal
        else
          block = parse_block
          default = block.body[0] if block && block.body.list.length == 1
        end
      else
        block = (@suppress_block || (is_var && !args && !@last_call_parens)) ? nil : parse_block
      end

      node = if block
               Call.new(nil, name, args || [], block, parens: @last_call_parens)
             elsif args
               Call.new(nil, name, args, nil, parens: @last_call_parens)
             else
               Var.new(name)
             end

      node.default = default if default && node.is_a?(Call)

      node.set_location(loc_file, loc_row, loc_col)
      node
    end

    def parse_call_args
      case @token.type
      when :"{"
        nil
      when :"("
        next_token_skip_whitespace_all

        if @token.type == :")"
          next_token_skip_space
          @last_call_parens = true
          return EMPTY_ARGS
        end

        args = []
        while @token.type != :")"
          if @token.type?(:"*")
            next_token
            if @token.type?(:"*")
              # ** double splat at call site
              next_token
              args << Splat.new(Splat.new(parse_expression))
            else
              args << Splat.new(parse_expression)
            end
          elsif @token.type?(:"**")
            next_token
            args << Splat.new(Splat.new(parse_expression))
          elsif @token.type?(:"&")
            # &block at call site
            next_token
            args << Call.new(nil, "&", [parse_expression])
          elsif keyword_label_token?
            # Keyword argument: name: value
            key = @token.value.to_s
            next_token  # past label
            next_token_skip_whitespace_all  # past :
            value = parse_expression
            args << HashLiteral.new([[StringLiteral.new(key), value]])
          else
            arg = parse_expression
            if @token.type?(:"=>")
              next_token_skip_whitespace_all
              arg = HashLiteral.new([[arg, parse_expression]])
            end
            args << arg
          end
          skip_whitespace_all

          if @token.type?(:",")
            next_token_skip_whitespace_all
          end
        end

        next_token_skip_space
        @last_call_parens = true
        args
      when :SP
        # Inside an `in (A B C)` tuple, space separates tuple elements, not
        # paren-less call args — suppress spaced-arg consumption so each
        # element parses as its own expression (otherwise `(A B)` becomes the
        # call `A(B)`).
        return nil if @no_spaced_call_args

        next_token

        if call_arg_start?
          args = []

          until end_token? || spaced_call_arg_end?
            if keyword_label_token? || named_label_token?
              # Keyword argument: name: value
              key = @token.value.to_s
              next_token  # past label
              next_token_skip_space  # past :
              value = parse_assignment
              args << HashLiteral.new([[StringLiteral.new(key), value]])
            else
              arg = parse_assignment
              if @token.type?(:"=>")
                next_token_skip_space
                arg = HashLiteral.new([[arg, parse_assignment]])
              end
              args << arg
            end
            skip_space

            if @token.comma?
              next_token_skip_whitespace
            else
              break
            end
          end

          args
        end
      end
    end

    def parse_block(same_line: nil)
      if @token.type?(:"{")
        # If same_line is given, only parse { as block if on the same line.
        # A { on a later line after dedent is a hash literal, not a block.
        return nil if same_line && @token.row != same_line
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

      expressions = []
      skip_whitespace_all
      until @token.type?(:"}")
        expressions << parse_expression
        skip_whitespace_all
      end
      body = List.from(expressions)

      consume :"}"

      Block.new(args, body)
    end

    # receiver.method(params) -> (args)
    #   ...expressions        ^-------- HERE
    # Also supports: -> (args) { body }
    def parse_block_multiline
      next_token_skip_space

      args = []

      if @token.type?(:"(")
        next_token_skip_space

        until @token.type?(:")")
          if @token.type?(:"*")
            next_token_skip_space
            next_token_skip_space if @token.type?(:"*")
          end
          unexpected unless identifier_name_token?

          args << Arg.new(@token.value)

          next_token_skip_space
          next_token_skip_space if @token.comma?
        end

        next_token
      end

      skip_space

      if @token.type?(:"{") && !looks_like_hash?
        # Inline brace block: ->(x) { body }
        next_token_skip_whitespace_all

        expressions = []
        until @token.type?(:"}")
          expressions << parse_expression
          skip_whitespace_all
        end
        body = List.from(expressions)

        consume :"}"
      elsif @token.type?(:NL) || @token.type?(:";")
        skip_whitespace
        if @token.type?(:INDENT)
          body = with_indent { parse_body }
        else
          body = List.new
        end
      elsif @token.type?(:EOF) || @token.type?(:DEDENT)
        body = List.new
      else
        # Inline expression: ->(x) x * 2, ->(x) return false unless x
        # Also handles hash literals: ->(x) {"key": x}
        body = parse_assignment_no_control
      end

      Block.new(args, body)
    end

    # Peek ahead to distinguish { key: val } (hash) from { body } (block).
    # Scans past { and whitespace to see if first content is "str": or id:
    def looks_like_hash?
      return false unless @token.type?(:"{")
      # check() peeks at the raw source after current scan position
      check(/\s*(?:"[^"]*"\s*:|[a-z_][a-z0-9_]*\s*:|})/)
    end

    def parse_if
      loc_file = @token.file
      loc_row = @token.row
      loc_col = @token.col
      next_token_skip_whitespace
      condition = parse_assignment_no_control

      # Inline if-then-else: if condition then body else body
      if @token.keyword?(:then)
        next_token_skip_space
        body = parse_assignment_no_control
        else_block = nil
        skip_space
        if @token.keyword?(:else)
          next_token_skip_space
          else_block = parse_assignment_no_control
        end
        node = If.new(condition, body, else_block)
        node.set_location(loc_file, loc_row, loc_col)
        return node
      end

      skip_statement_end
      body = with_indent { parse_body }

      if @token.keyword?(:elsif)
        else_block = parse_if
      elsif @token.keyword?(:else)
        next_token
        skip_statement_end
        else_block = with_indent { parse_body }
      end

      node = If.new(condition, body, else_block)
      node.set_location(loc_file, loc_row, loc_col)
      node
    end

    def parse_unless
      loc_file = @token.file
      loc_row = @token.row
      loc_col = @token.col
      next_token_skip_whitespace
      condition = parse_assignment_no_control
      skip_statement_end
      body = with_indent { parse_body }

      else_block = nil
      if @token.keyword?(:else)
        next_token
        skip_statement_end
        else_block = with_indent { parse_body }
      end

      node = If.new(Not.new(condition), body, else_block)
      node.set_location(loc_file, loc_row, loc_col)
      node
    end

    def parse_loop(klass)
      loc_file = @token.file
      loc_row = @token.row
      loc_col = @token.col
      next_token_skip_whitespace
      condition = parse_assignment_no_control
      skip_statement_end
      body = with_indent { parse_body }
      node = klass.new(condition, body, true)
      node.set_location(loc_file, loc_row, loc_col)
      node
    end

    def parse_loop_forever
      loc_file = @token.file
      loc_row = @token.row
      loc_col = @token.col
      next_token
      skip_statement_end
      body = with_indent { parse_body }
      node = While.new(Boolean.new(true), body, true)
      node.set_location(loc_file, loc_row, loc_col)
      node
    end

    def parse_yield
      next_token
      args = []
      unless @token.type?(:NL) || @token.type?(:EOF) || @token.type?(:DEDENT)
        skip_space
        unless @token.suffix?
          args << parse_assignment_no_control
          while @token.type?(:",")
            next_token_skip_whitespace
            args << parse_assignment_no_control
          end
        end
      end
      Yield.new(args)
    end

    # &(args) — invoke the implicit block
    def parse_block_call
      next_token_skip_whitespace
      args = []
      unless @token.type?(:")")
        args << parse_expression
        while @token.type?(:",")
          next_token_skip_whitespace
          args << parse_expression
        end
      end
      consume :")"
      Yield.new(args)
    end

    def parse_return
      next_token
      if @token.type?(:NL) || @token.type?(:EOF) || @token.type?(:DEDENT)
        Return.new(nil)
      else
        skip_space
        @token.suffix? ? Return.new(nil) : Return.new(parse_assignment_no_control)
      end
    end

    def parse_break
      next_token
      if @token.type?(:NL) || @token.type?(:EOF) || @token.type?(:DEDENT)
        Break.new(nil)
      else
        skip_space
        @token.suffix? ? Break.new(nil) : Break.new(parse_assignment_no_control)
      end
    end

    def parse_next
      next_token
      if @token.type?(:NL) || @token.type?(:EOF) || @token.type?(:DEDENT)
        Next.new(nil)
      else
        skip_space
        @token.suffix? ? Next.new(nil) : Next.new(parse_assignment_no_control)
      end
    end

    def parse_quantity_token
      num_str, unit_str, num_type = @token.value
      number = case num_type
               when :FLOAT   then Float.new(num_str)
               when :DECIMAL then Decimal.new(num_str)
               else               Int.new(num_str)
               end
      QuantityLiteral.new(number, unit_str)
    end

    # `5(2)` or `2.1232442(2)` (concise uncertainty notation, no unit).
    # The (N) gives uncertainty in the last given digit.
    def parse_measurement_token
      num_str, num_type, uncert_str = @token.value
      number = number_node_for(num_str, num_type)
      MeasurementLiteral.new(number, concise_uncertainty(num_str, uncert_str))
    end

    # `5.0(1) m` — measurement with unit.
    def parse_measured_quantity_token
      num_str, unit_str, num_type, uncert_str = @token.value
      number = number_node_for(num_str, num_type)
      meas = MeasurementLiteral.new(number, concise_uncertainty(num_str, uncert_str))
      QuantityLiteral.new(meas, unit_str)
    end

    def number_node_for(num_str, num_type)
      case num_type
      when :FLOAT   then Float.new(num_str)
      when :DECIMAL then Decimal.new(num_str)
      else               Int.new(num_str)
      end
    end

    # `2.13(5)` → 0.05 (5 in the hundredths place).
    # `1500(20)` (integer) → 20 (whole units).
    def concise_uncertainty(num_str, uncert_digits_str)
      digits = uncert_digits_str.to_f
      if num_str.include?(".")
        decimal_places = num_str.split(".", 2)[1].length
        digits * 10.0**(-decimal_places)
      else
        digits
      end
    end

    private

    def check_for(*types)
      return if types.include?(@token.type)

      error "expecting: #{types.join ', '} (not '#{@token.type}')"
    end

    def check_for_one(type)
      return if @token.type?(type)

      error "expecting: #{type} (not '#{@token.type}')"
    end

    def check_valid_method_name
      if %w[is_a? responds_to? nil?].include?(@token.value)
        error "'#{@token.value}' can't be redefined"
      end
    end

    def check_void
      return unless @token.type?(:KEYWORD)

      case @token.value
      when :break, :next, :return
        error "void value expression"
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
      when *%i[ } \] %} EOF]
        true
      when :KEYWORD
        %i[else elsif when in rescue ensure then].include?(@token.value)
      else
        false
      end
    end

    def call_arg_start?
      case @token.type
      when :CHAR, :DECIMAL, :INT, :FLOAT, :ID, :NAME, :CONSTANT, :"(", :"&(", :"!", :"[", :STRING, :REGEX,
           :REGEX_CAPTURE, :SYMBOL
        true
      when :KEYWORD
        soft_identifier_keyword?
      else
        false
      end
    end

    def spaced_call_arg_end?
      case @token.type
      when :NL, :";", :EOF, :":"
        true
      else
        false
      end
    end

    def first_child_with_location(node)
      node.children do |child|
        return child if child.location_row

        descendant = first_child_with_location(child)
        return descendant if descendant
      end

      nil
    end

    def node_and_next_token(node)
      locate(node)
      next_token
      node
    end

    def open(name)
      @unclosed.push Unclosed.new(name, @token.file, @token.row, @token.col)

      begin
        value = yield
      ensure
        @unclosed.pop
      end

      value
    end

    def push_var(node)
      case node
      when Arg, Var
        push_var_name node.name.to_s
      else
        # nothing
      end

      node
    end

    def push_var_name(name)
      @scopes.last.add(name)
    end

    def unexpected(msg = nil, token = @token)
      if msg
        error "unexpected token: #{token} (#{msg})"
      else
        error "unexpected token: #{token}"
      end
    end

    def var?(name)
      name = name.to_s
      name == "self" || var_in_scope?(name)
    end

    def var_in_scope?(name)
      @scopes.last.include?(name)
    end

    def with_indent(&block)
      consume :INDENT

      yield.tap do
        consume :DEDENT unless @token.type?(:EOF)
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

    # Create a new scope with the same variables as the current scope
    def with_lexical_scope
      scope = @scopes.last.dup
      @scopes.push(scope)
      yield
    ensure
      @scopes.pop
    end
  end
end
