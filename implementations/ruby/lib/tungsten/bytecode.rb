# frozen_string_literal: true

module Tungsten
  module Bytecode
    # Opcodes
    OP_NOP          = 0
    OP_LOAD_CONST   = 1   # [op, value]       → push constant
    OP_LOAD_LOCAL   = 2   # [op, depth, slot]  → push variable
    OP_STORE_LOCAL  = 3   # [op, depth, slot]  → pop and store
    OP_LOAD_NIL     = 4   # [op]               → push nil
    OP_LOAD_TRUE    = 5   # [op]               → push true
    OP_LOAD_FALSE   = 6   # [op]               → push false
    OP_POP          = 7   # [op]               → discard top
    OP_DUP          = 8   # [op]               → duplicate top

    # Arithmetic (pop 2, push 1)
    OP_ADD          = 10
    OP_SUB          = 11
    OP_MUL          = 12
    OP_DIV          = 13
    OP_MOD          = 14

    # Comparison (pop 2, push 1)
    OP_EQ           = 20
    OP_NEQ          = 21
    OP_LT           = 22
    OP_GT           = 23
    OP_LTE          = 24
    OP_GTE          = 25

    # Control flow
    OP_JUMP         = 30  # [op, target]
    OP_JUMP_FALSE   = 31  # [op, target]       → pop, jump if falsy
    OP_JUMP_TRUE    = 32  # [op, target]       → pop, jump if truthy

    # Functions
    OP_RETURN       = 40  # [op]               → return top of stack
    OP_PUTS         = 41  # [op]               → pop and print with newline

    # Fallback: evaluate an AST node directly (for unsupported nodes)
    OP_EVAL_NODE    = 50  # [op, node]         → push result of evaluate(node)

    # Instruction is a flat array: [op, arg1, arg2, op, arg1, ...]
    # IP advances by instruction width.

    WIDTHS = {
      OP_NOP => 1, OP_LOAD_CONST => 2, OP_LOAD_LOCAL => 3, OP_STORE_LOCAL => 3,
      OP_LOAD_NIL => 1, OP_LOAD_TRUE => 1, OP_LOAD_FALSE => 1,
      OP_POP => 1, OP_DUP => 1,
      OP_ADD => 1, OP_SUB => 1, OP_MUL => 1, OP_DIV => 1, OP_MOD => 1,
      OP_EQ => 1, OP_NEQ => 1, OP_LT => 1, OP_GT => 1, OP_LTE => 1, OP_GTE => 1,
      OP_JUMP => 2, OP_JUMP_FALSE => 2, OP_JUMP_TRUE => 2,
      OP_RETURN => 1, OP_PUTS => 1,
      OP_EVAL_NODE => 2,
    }.freeze

    Program = Struct.new(:code, :local_names)

    class Compiler
      Unsupported = Class.new(StandardError)

      BINARY_OPS = {
        :+ => OP_ADD,
        :- => OP_SUB,
        :* => OP_MUL,
        :/ => OP_DIV,
        :% => OP_MOD,
        :== => OP_EQ,
        :!= => OP_NEQ,
        :< => OP_LT,
        :> => OP_GT,
        :<= => OP_LTE,
        :>= => OP_GTE
      }.freeze

      attr_reader :code

      def initialize(params = EMPTY_ARGS)
        @code = []
        @local_slots = {}
        @local_names = []
        params.each_with_index { |param, i| register_local(param.name, i) }
      end

      def compile(node)
        emit_node(node)
        Program.new(@code, @local_names.freeze)
      rescue Unsupported
        nil
      end

      private

      EMPTY_ARGS = [].freeze

      def register_local(name, slot = @local_names.length)
        @local_slots[name] = slot
        @local_names[slot] = name
        slot
      end

      def local_slot(name)
        @local_slots[name]
      end

      def unsupported!
        raise Unsupported
      end

      def emit_node(node, allow_new_locals: true)
        case node
        when AST::ArrayLiteral
          unsupported!

        when AST::List
          node.list.each_with_index do |expr, i|
            emit_node(expr, allow_new_locals:)
            # Pop intermediate results (keep last)
            @code << OP_POP if i < node.list.length - 1
          end

        when AST::Int, AST::WValue
          @code << OP_LOAD_CONST << node.value
        when AST::Float
          @code << OP_LOAD_CONST << node.value
        when AST::Decimal
          @code << OP_LOAD_CONST << node.value
        when AST::StringLiteral
          @code << OP_LOAD_CONST << node.value
        when AST::Boolean
          @code << (node.value ? OP_LOAD_TRUE : OP_LOAD_FALSE)
        when AST::Nil
          @code << OP_LOAD_NIL

        when AST::Var
          slot = local_slot(node.name)
          if slot
            @code << OP_LOAD_LOCAL << 0 << slot
          else
            @code << OP_EVAL_NODE << node
          end

        when AST::Assign
          unsupported! unless node.name.is_a?(AST::Var)

          name = node.name.name
          slot = local_slot(name)
          emit_node(node.value, allow_new_locals:)
          slot ||= allow_new_locals ? register_local(name) : unsupported!
          @code << OP_STORE_LOCAL << 0 << slot

        when AST::BinaryOp
          op = BINARY_OPS[node.operator] || unsupported!
          emit_node(node.left, allow_new_locals:)
          emit_node(node.right, allow_new_locals:)
          @code << op

        when AST::If
          emit_node(node.condition, allow_new_locals: false)
          jump_false_idx = @code.size
          @code << OP_JUMP_FALSE << 0  # placeholder

          emit_node(node.then_block, allow_new_locals: false)

          if node.else_block && !node.else_block.empty?
            jump_end_idx = @code.size
            @code << OP_JUMP << 0  # placeholder
            @code[jump_false_idx + 1] = @code.size  # patch false branch
            emit_node(node.else_block, allow_new_locals: false)
            @code[jump_end_idx + 1] = @code.size  # patch end
          else
            @code[jump_false_idx + 1] = @code.size
            @code << OP_LOAD_NIL  # if with no else produces nil
          end

        when AST::While
          if node.check_first == true
            loop_start = @code.size
            emit_node(node.condition, allow_new_locals: false)
            jump_false_idx = @code.size
            @code << OP_JUMP_FALSE << 0

            emit_node(node.body, allow_new_locals: false)
            @code << OP_POP  # discard body result each iteration
            @code << OP_JUMP << loop_start
            @code[jump_false_idx + 1] = @code.size
            @code << OP_LOAD_NIL
          else
            unsupported!
          end

        when AST::Print
          unsupported! unless node.args.length == 1

          emit_node(node.args.first, allow_new_locals:)
          @code << OP_PUTS

        when AST::Return
          if node.value
            emit_node(node.value, allow_new_locals:)
          else
            @code << OP_LOAD_NIL
          end
          @code << OP_RETURN

        when AST::AssignOp
          unsupported! unless node.name.is_a?(AST::Var)

          slot = local_slot(node.name.name) || unsupported!
          op = BINARY_OPS[node.operator] || unsupported!
          @code << OP_LOAD_LOCAL << 0 << slot
          emit_node(node.value, allow_new_locals:)
          @code << op
          @code << OP_STORE_LOCAL << 0 << slot

        when AST::Not
          emit_node(node.exp, allow_new_locals:)
          # Inline not: jump_true → push false, else push true
          jt = @code.size
          @code << OP_JUMP_TRUE << 0
          @code << OP_LOAD_TRUE
          je = @code.size
          @code << OP_JUMP << 0
          @code[jt + 1] = @code.size
          @code << OP_LOAD_FALSE
          @code[je + 1] = @code.size

        else
          unsupported!
        end
      end
    end

    class VM
      def initialize(interpreter)
        @interp = interpreter
      end

      def execute(program, env)
        code = program.code
        local_names = program.local_names
        ip = 0
        stack = []
        len = code.size

        while ip < len
          op = code[ip]

          case op
          when OP_LOAD_CONST
            stack << code[ip + 1]
            ip += 2

          when OP_LOAD_LOCAL
            depth = code[ip + 1]
            slot = code[ip + 2]
            e = env
            depth.times { e = e.parent }
            if depth.zero? && (name = local_names[slot]) && e.slot_index(name) != slot
              raise Tungsten::Error, "Undefined variable '#{name}'"
            end
            stack << e.get_slot(slot)
            ip += 3

          when OP_STORE_LOCAL
            depth = code[ip + 1]
            slot = code[ip + 2]
            e = env
            depth.times { e = e.parent }
            if depth.zero? && (name = local_names[slot]) && e.slot_index(name) != slot
              e.define_slot(name, slot, stack.last)
            else
              e.set_slot(slot, stack.last)
            end
            ip += 3

          when OP_LOAD_NIL
            stack << nil
            ip += 1
          when OP_LOAD_TRUE
            stack << true
            ip += 1
          when OP_LOAD_FALSE
            stack << false
            ip += 1

          when OP_POP
            stack.pop
            ip += 1
          when OP_DUP
            stack << stack.last
            ip += 1

          when OP_ADD
            b = stack.pop; a = stack.pop
            stack << (a + b)
            ip += 1
          when OP_SUB
            b = stack.pop; a = stack.pop
            stack << (a - b)
            ip += 1
          when OP_MUL
            b = stack.pop; a = stack.pop
            stack << (a * b)
            ip += 1
          when OP_DIV
            b = stack.pop; a = stack.pop
            stack << (a / b)
            ip += 1
          when OP_MOD
            b = stack.pop; a = stack.pop
            stack << (a % b)
            ip += 1

          when OP_EQ
            b = stack.pop; a = stack.pop
            stack << (a == b)
            ip += 1
          when OP_NEQ
            b = stack.pop; a = stack.pop
            stack << (a != b)
            ip += 1
          when OP_LT
            b = stack.pop; a = stack.pop
            stack << (a < b)
            ip += 1
          when OP_GT
            b = stack.pop; a = stack.pop
            stack << (a > b)
            ip += 1
          when OP_LTE
            b = stack.pop; a = stack.pop
            stack << (a <= b)
            ip += 1
          when OP_GTE
            b = stack.pop; a = stack.pop
            stack << (a >= b)
            ip += 1

          when OP_JUMP
            ip = code[ip + 1]
          when OP_JUMP_FALSE
            val = stack.pop
            if val.nil? || val == false
              ip = code[ip + 1]
            else
              ip += 2
            end
          when OP_JUMP_TRUE
            val = stack.pop
            if !val.nil? && val != false
              ip = code[ip + 1]
            else
              ip += 2
            end

          when OP_RETURN
            return stack.pop

          when OP_PUTS
            val = stack.pop
            $stdout.puts(val.is_a?(String) ? val : @interp.send(:w_to_s, val))
            stack << nil
            ip += 1

          when OP_EVAL_NODE
            node = code[ip + 1]
            old_env = @interp.instance_variable_get(:@env)
            @interp.instance_variable_set(:@env, env)
            stack << @interp.evaluate(node)
            @interp.instance_variable_set(:@env, old_env)
            ip += 2

          else
            raise "Unknown bytecode op: #{op}"
          end
        end

        stack.last
      end
    end

    # Check if a function body is suitable for bytecode compilation.
    def self.compilable?(node)
      !!Compiler.new.compile(node)
    end
  end
end
