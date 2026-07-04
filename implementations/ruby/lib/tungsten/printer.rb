# frozen_string_literal: true

module Tungsten
  # Visitor-based AST printer. Produces canonical Tungsten source from an AST.
  #
  # Follows Crystal's ToSVisitor pattern: each visit method appends to @str
  # and returns false to prevent the default children traversal (the printer
  # controls its own traversal order).
  #
  # Usage:
  #   ast = Tungsten::Parser.parse(source)
  #   puts ast.to_s          # uses Printer internally
  #   puts Printer.print(ast)
  #
  class Printer < Visitor
    INDENT = "  "

    def self.print(node)
      printer = new
      node.accept(printer)
      printer.to_s
    end

    def initialize
      @str = +""
      @depth = 0
      @needs_indent = false
    end

    def to_s
      @str.rstrip
    end

    # ── List / Expressions ─────────────────────────────────────────────

    def list(node, _parent)
      node.list.each_with_index do |child, i|
        child.accept(self)
        newline unless i == node.list.size - 1
      end
      false
    end

    # ── Literals ───────────────────────────────────────────────────────

    def int(node, _parent)
      append node.value.to_s
      false
    end

    def w_value(node, _parent)
      append node.raw
      false
    end

    def float(node, _parent)
      append node.value.to_s
      false
    end

    def decimal(node, _parent)
      append node.value.to_s
      false
    end

    def boolean(node, _parent)
      append node.value.to_s
      false
    end

    def nil(node, _parent)
      append "nil"
      false
    end

    def string_literal(node, _parent)
      append "\"#{escape_string(node.value)}\""
      false
    end

    def string_interpolation(node, _parent)
      append "\""
      node.parts.each do |part|
        if part.is_a?(AST::StringLiteral)
          @str << escape_string(part.value)
        else
          @str << "["
          part.accept(self)
          @str << "]"
        end
      end
      @str << "\""
      false
    end

    def char(node, _parent)
      append "U+#{node.value.ord.to_s(16).upcase.rjust(4, "0")}"
      false
    end

    def symbol(node, _parent)
      val = node.value.to_s
      append val.start_with?(":") ? val : ":#{val}"
      false
    end

    def range_literal(node, _parent)
      node.from.accept(self)
      @str << (node.exclusive ? "..." : "..")
      node.to.accept(self)
      false
    end

    def array_literal(node, _parent)
      append "["
      node.list.each_with_index do |el, i|
        @str << ", " if i > 0
        el.accept(self)
      end
      @str << "]"
      false
    end

    def hash_literal(node, _parent)
      append "{"
      node.entries.each_with_index do |(k, v), i|
        @str << ", " if i > 0
        k.accept(self)
        @str << ": "
        v.accept(self)
      end
      @str << "}"
      false
    end

    def tuple(node, _parent)
      append "("
      node.elements.each_with_index do |el, i|
        @str << ", " if i > 0
        el.accept(self)
      end
      @str << ")"
      false
    end

    def magic_constant(node, _parent)
      append node.value.to_s
      false
    end

    def quantity_literal(node, _parent)
      node.number.accept(self)
      @str << " #{node.unit_string}"
      false
    end

    def currency_literal(node, _parent)
      append "#{node.symbol}#{node.value_str}"
      false
    end

    def percentage_literal(node, _parent)
      append "#{node.value_str}%"
      false
    end

    # Network / temporal literals
    def ip4(node, _parent)       = (append(node.value); false)
    def ip6(node, _parent)       = (append(node.value); false)
    def cidr4(node, _parent)     = (append(node.value); false)
    def cidr6(node, _parent)     = (append(node.value); false)
    def uuid(node, _parent)      = (append(node.value); false)
    def date(node, _parent)      = (append(node.value); false)
    def date_time(node, _parent) = (append(node.value); false)
    def time_literal(node, _parent) = (append(node.value); false)
    def duration(node, _parent)  = (append(node.value); false)
    def month(node, _parent)     = (append(node.value); false)
    def week(node, _parent)      = (append(node.value); false)

    def key_literal(node, _parent)
      append "#[#{node.value}]"
      false
    end

    def byte_array_literal(node, _parent)
      hex = node.value.map { |b| b.to_s(16).rjust(2, "0") }.join(" ")
      append(node.value.empty? ? "« »" : "« #{hex} »")
      false
    end

    def byte_array_interpolation(node, _parent)
      append "« "
      node.parts.each_with_index do |part, i|
        @str << " " if i > 0
        if part.is_a?(AST::ByteArrayLiteral)
          @str << part.value.map { |b| b.to_s(16).rjust(2, "0") }.join(" ")
        else
          @str << "["
          part.accept(self)
          @str << "]"
        end
      end
      @str << " »"
      false
    end

    # ── Variables ──────────────────────────────────────────────────────

    def var(node, _parent)
      append node.name.to_s
      false
    end

    def instance_var(node, _parent)
      append node.name.to_s
      false
    end

    def global_var(node, _parent)
      append node.name.to_s
      false
    end

    def path(node, _parent)
      append node.names.join("::")
      false
    end

    # ── Operators ──────────────────────────────────────────────────────

    def binary_op(node, _parent)
      node.left.accept(self)
      @str << " #{node.operator} "
      node.right.accept(self)
      false
    end

    def not(node, _parent)
      append "!"
      node.exp.accept(self)
      false
    end

    def and(node, _parent)
      node.left.accept(self)
      @str << " && "
      node.right.accept(self)
      false
    end

    def or(node, _parent)
      node.left.accept(self)
      @str << " || "
      node.right.accept(self)
      false
    end

    def splat(node, _parent)
      append "*"
      node.exp.accept(self)
      false
    end

    # ── Assignment ─────────────────────────────────────────────────────

    def assign(node, _parent)
      node.name.accept(self)
      @str << " = "
      node.value.accept(self)
      false
    end

    def assign_op(node, _parent)
      node.name.accept(self)
      @str << " #{node.operator}= "
      node.value.accept(self)
      false
    end

    # ── Calls ──────────────────────────────────────────────────────────

    def call(node, _parent)
      if node.obj
        node.obj.accept(self)
        @str << ".#{node.name}"
      else
        append node.name.to_s
      end

      if node.args && !node.args.empty?
        @str << "("
        node.args.each_with_index do |arg, i|
          @str << ", " if i > 0
          arg.accept(self)
        end
        @str << ")"
      end

      if node.block
        @str << " "
        node.block.accept(self)
      end
      false
    end

    def super(node, _parent)
      append "super"
      unless node.args.empty?
        @str << "("
        node.args.each_with_index do |arg, i|
          @str << ", " if i > 0
          arg.accept(self)
        end
        @str << ")"
      end
      false
    end

    # ── Print / Write ──────────────────────────────────────────────────

    def print(node, _parent)
      append "<< "
      node.args.each_with_index do |arg, i|
        @str << ", " if i > 0
        arg.accept(self)
      end
      false
    end

    def write(node, _parent)
      append "<- "
      node.args.each_with_index do |arg, i|
        @str << ", " if i > 0
        arg.accept(self)
      end
      false
    end

    # ── Control Flow ───────────────────────────────────────────────────

    def if(node, _parent)
      append "if "
      node.condition.accept(self)
      newline
      with_indent { node.then_block.accept(self) }

      if node.else_block && !node.else_block.empty?
        newline
        if node.else_block.is_a?(AST::If)
          append "els"
          node.else_block.accept(self)
        else
          append "else"
          newline
          with_indent { node.else_block.accept(self) }
        end
      end
      false
    end

    def while(node, _parent)
      append "while "
      node.condition.accept(self)
      newline
      with_indent { node.body.accept(self) }
      false
    end

    def case_expr(node, _parent)
      append "case"
      if node.receiver
        @str << " "
        node.receiver.accept(self)
      end
      newline

      node.whens.each do |conditions, body|
        append "when "
        conditions.each_with_index do |cond, i|
          @str << ", " if i > 0
          cond.accept(self)
        end
        newline
        with_indent { body.accept(self) }
        newline
      end

      if node.else_body && !node.else_body.empty?
        append "else"
        newline
        with_indent { node.else_body.accept(self) }
        newline
      end
      false
    end

    def begin(node, _parent)
      append "begin"
      newline
      with_indent { node.body.accept(self) }

      if node.rescue_body && !node.rescue_body.empty?
        newline
        append "rescue"
        @str << " #{node.rescue_var}" if node.rescue_var
        newline
        with_indent { node.rescue_body.accept(self) }
      end

      if node.ensure_body && !node.ensure_body.empty?
        newline
        append "ensure"
        newline
        with_indent { node.ensure_body.accept(self) }
      end
      false
    end

    def with(node, _parent)
      append "with "
      node.bindings.each_with_index do |(var, expr), i|
        @str << ", " if i > 0
        var.accept(self)
        @str << " in "
        expr.accept(self)
      end
      newline
      with_indent { node.body.accept(self) }
      false
    end

    # ── Definitions ────────────────────────────────────────────────────

    def def(node, _parent)
      emit_def(node, "->")
      false
    end

    def fn(node, _parent)
      emit_def(node, "fn")
      false
    end

    def class_def(node, _parent)
      append "+ #{node.name}"
      @str << "[#{node.class_role}]" if node.class_role
      @str << " < #{node.superclass}" if node.superclass
      newline
      with_indent { node.body.accept(self) }
      false
    end

    def trait_def(node, _parent)
      append "trait #{node.name}"
      newline
      with_indent { node.body.accept(self) }
      false
    end

    def module_def(node, _parent)
      append "module #{node.name}"
      newline
      with_indent { node.body.accept(self) }
      false
    end

    def block(node, _parent)
      args = node.args&.map { |a| a.name.to_s }&.join(", ")
      if args && !args.empty?
        append "->(#{args})"
      else
        append "->()"
      end

      # Single-expression body: inline
      if node.body.is_a?(AST::List) && node.body.list.size <= 1
        @str << " "
        node.body.accept(self)
      else
        newline
        with_indent { node.body.accept(self) }
      end
      false
    end

    def arg(node, _parent)
      append node.name.to_s
      if node.default
        @str << " = "
        node.default.accept(self)
      end
      false
    end

    # ── Keywords ───────────────────────────────────────────────────────

    def return(node, _parent)
      append "return"
      if node.value
        @str << " "
        node.value.accept(self)
      end
      false
    end

    def break(node, _parent)
      append "break"
      if node.value
        @str << " "
        node.value.accept(self)
      end
      false
    end

    def next(node, _parent)
      append "next"
      if node.value
        @str << " "
        node.value.accept(self)
      end
      false
    end

    def yield(node, _parent)
      append "yield"
      unless node.args.empty?
        @str << " "
        node.args.each_with_index do |arg, i|
          @str << ", " if i > 0
          arg.accept(self)
        end
      end
      false
    end

    def raise(node, _parent)
      append "raise "
      node.value.accept(self)
      false
    end

    def use(node, _parent)
      append "use \"#{node.path}\""
      false
    end

    def is(node, _parent)
      append "is #{node.trait_name}"
      false
    end

    def alias(node, _parent)
      append "alias #{node.to} #{node.from}"
      false
    end

    private

    def emit_def(node, keyword)
      name = node.name
      args = node.args

      if name
        append "#{keyword} #{name}"
      else
        append keyword
      end

      if args && !args.empty?
        @str << "("
        args.each_with_index do |a, i|
          @str << ", " if i > 0
          a.accept(self)
        end
        @str << ")"
      end

      if node.body && !node.body.empty?
        newline
        with_indent { node.body.accept(self) }
      end
    end

    def append(str)
      if @needs_indent
        @str << (INDENT * @depth)
        @needs_indent = false
      end
      @str << str
    end

    def newline
      @str << "\n"
      @needs_indent = true
    end

    def indent
      @depth += 1
      yield
      @depth -= 1
    end

    def with_indent(&block)
      indent(&block)
    end

    def escape_string(str)
      str.gsub("\\", "\\\\").gsub("\"", "\\\"").gsub("\n", "\\n").gsub("\t", "\\t")
    end
  end
end
