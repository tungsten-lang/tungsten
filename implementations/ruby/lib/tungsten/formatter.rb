# frozen_string_literal: true

module Tungsten
  class Formatter
    INDENT = "  "

    def initialize
      @depth = 0
    end

    def format(source)
      ast = Parser.parse(source)
      emit(ast).rstrip + "\n"
    end

    private

    def emit(node)
      case node
      when AST::List
        node.list.map { |n| emit(n) }.join("\n")
      when AST::Print
        indent + "<< " + node.args.map { |a| emit(a) }.join(", ")
      when AST::Write
        indent + "<- " + node.args.map { |a| emit(a) }.join(", ")
      when AST::Int
        node.value.to_s
      when AST::WValue
        node.raw
      when AST::Float
        node.value.to_s
      when AST::Decimal
        node.value.to_s
      when AST::Boolean
        node.value.to_s
      when AST::Nil
        "nil"
      when AST::StringLiteral
        "\"#{node.value}\""
      when AST::StringInterpolation
        parts = node.parts.map do |p|
          p.is_a?(AST::StringLiteral) ? p.value : "[#{emit(p)}]"
        end
        "\"#{parts.join}\""
      when AST::Symbol
        node.value.to_s.start_with?(":") ? node.value.to_s : ":#{node.value}"
      when AST::ArrayLiteral
        "[#{node.list.map { |e| emit(e) }.join(", ")}]"
      when AST::HashLiteral
        entries = node.entries.map { |k, v| "#{emit(k)}: #{emit(v)}" }
        "{#{entries.join(", ")}}"
      when AST::ByteArrayLiteral
        hex = node.value.map { |b| b.to_s(16).rjust(2, "0") }.join(" ")
        node.value.empty? ? "« »" : "« #{hex} »"
      when AST::ByteArrayInterpolation
        parts_str = node.parts.map do |p|
          if p.is_a?(AST::ByteArrayLiteral)
            p.value.map { |b| b.to_s(16).rjust(2, "0") }.join(" ")
          else
            "[#{emit(p)}]"
          end
        end
        "« #{parts_str.join(" ")} »"
      when AST::Var
        node.name.to_s
      when AST::InstanceVar
        node.name.to_s
      when AST::GlobalVar
        node.name.to_s
      when AST::Path
        node.names.join("::")
      when AST::Assign
        indent + "#{emit(node.name)} = #{emit(node.value)}"
      when AST::AssignOp
        indent + "#{emit(node.name)} #{node.operator}= #{emit(node.value)}"
      when AST::BinaryOp
        "#{emit(node.left)} #{node.operator} #{emit(node.right)}"
      when AST::Not
        "!#{emit(node.exp)}"
      when AST::And
        "#{emit(node.left)} && #{emit(node.right)}"
      when AST::Or
        "#{emit(node.left)} || #{emit(node.right)}"
      when AST::Call
        emit_call(node)
      when AST::ClassDef
        emit_class(node)
      when AST::TraitDef
        emit_trait(node)
      when AST::ModuleDef
        emit_module(node)
      when AST::Def
        emit_def(node)
      when AST::Fn
        emit_def(node, keyword: "fn")
      when AST::If
        emit_if(node)
      when AST::While
        emit_while(node)
      when AST::Case, AST::CaseExpr
        emit_case(node)
      when AST::Begin
        emit_begin(node)
      when AST::Return
        node.value ? indent + "return #{emit(node.value)}" : indent + "return"
      when AST::Break
        node.value ? indent + "break #{emit(node.value)}" : indent + "break"
      when AST::Next
        node.value ? indent + "next #{emit(node.value)}" : indent + "next"
      when AST::Yield
        args = node.args.map { |a| emit(a) }.join(", ")
        args.empty? ? indent + "yield" : indent + "yield #{args}"
      when AST::Raise
        indent + "raise #{emit(node.value)}"
      when AST::Use
        indent + "use \"#{node.path}\""
      when AST::Super
        args = node.args.map { |a| emit(a) }.join(", ")
        args.empty? ? "super" : "super(#{args})"
      when AST::RangeLiteral
        op = node.exclusive ? "..." : ".."
        "#{emit(node.from)}#{op}#{emit(node.to)}"
      when AST::Splat
        "*#{emit(node.exp)}"
      when AST::Block
        emit_block(node)
      when AST::Is
        indent + "is #{node.trait_name}"
      when AST::Alias
        indent + "alias #{node.to} #{node.from}"
      when AST::With
        emit_with(node)
      when AST::Tuple
        "(#{node.elements.map { |e| emit(e) }.join(", ")})"
      when AST::MagicConstant
        node.value.to_s
      when AST::Arg
        node.default ? "#{node.name} = #{emit(node.default)}" : node.name.to_s
      else
        # Fallback for types we don't handle yet
        node.inspect
      end
    end

    def emit_call(node)
      result = ""
      if node.obj
        result = "#{emit(node.obj)}.#{node.name}"
      else
        result = node.name.to_s
      end

      if node.args && !node.args.empty?
        args = node.args.map { |a| emit(a) }.join(", ")
        result += "(#{args})"
      end

      if node.block
        result += " " + emit_block(node.block)
      end

      result
    end

    def emit_block(node)
      args = node.args&.map { |a| a.name.to_s }&.join(", ")
      header = args && !args.empty? ? "->(#{args})" : "->()"

      body = indented { emit(node.body) }
      if body.strip.count("\n") == 0
        "#{header} #{body.strip}"
      else
        "#{header}\n#{body}"
      end
    end

    def emit_class(node)
      header = indent + "+ #{node.name}"
      header += "[#{node.class_role}]" if node.class_role
      header += " < #{node.superclass}" if node.superclass
      body = indented { emit(node.body) }
      "#{header}\n#{body}"
    end

    def emit_trait(node)
      header = indent + "trait #{node.name}"
      body = indented { emit(node.body) }
      "#{header}\n#{body}"
    end

    def emit_module(node)
      header = indent + "module #{node.name}"
      body = indented { emit(node.body) }
      "#{header}\n#{body}"
    end

    def emit_def(node, keyword: "->")
      name = node.name
      args = node.args&.map { |a| emit(a) }&.join(", ")
      header = if name
                 args ? "#{indent}#{keyword} #{name}(#{args})" : "#{indent}#{keyword} #{name}"
               else
                 args ? "#{indent}#{keyword} (#{args})" : "#{indent}#{keyword}"
               end

      body = indented { emit(node.body) }
      if body.strip.empty?
        header
      else
        "#{header}\n#{body}"
      end
    end

    def emit_if(node)
      result = indent + "if #{emit(node.condition)}\n"
      result += indented { emit(node.then_block) }

      if node.else_block && !node.else_block.empty?
        if node.else_block.is_a?(AST::If)
          result += "\n#{indent}els#{emit_if_inner(node.else_block)}"
        else
          result += "\n#{indent}else\n"
          result += indented { emit(node.else_block) }
        end
      end

      result
    end

    def emit_if_inner(node)
      result = "if #{emit(node.condition)}\n"
      result += indented { emit(node.then_block) }

      if node.else_block && !node.else_block.empty?
        if node.else_block.is_a?(AST::If)
          result += "\n#{indent}els#{emit_if_inner(node.else_block)}"
        else
          result += "\n#{indent}else\n"
          result += indented { emit(node.else_block) }
        end
      end

      result
    end

    def emit_while(node)
      result = indent + "while #{emit(node.condition)}\n"
      result += indented { emit(node.body) }
      result
    end

    def emit_case(node)
      receiver = node.receiver ? " #{emit(node.receiver)}" : ""
      result = indent + "case#{receiver}\n"

      @depth += 1
      node.whens.each do |conditions, body|
        conds = conditions.map { |c| emit(c) }.join(", ")
        result += indent + "when #{conds}\n"
        result += indented { emit(body) } + "\n"
      end

      if node.else_body && !node.else_body.empty?
        result += indent + "else\n"
        result += indented { emit(node.else_body) } + "\n"
      end
      @depth -= 1

      result.rstrip
    end

    def emit_begin(node)
      result = indent + "begin\n"
      result += indented { emit(node.body) }
      if node.rescue_body && !node.rescue_body.empty?
        result += "\n#{indent}rescue"
        result += " #{node.rescue_var}" if node.rescue_var
        result += "\n"
        result += indented { emit(node.rescue_body) }
      end
      if node.ensure_body && !node.ensure_body.empty?
        result += "\n#{indent}ensure\n"
        result += indented { emit(node.ensure_body) }
      end
      result
    end

    def emit_with(node)
      bindings = node.bindings.map { |var, expr| "#{emit(var)} in #{emit(expr)}" }.join(", ")
      result = indent + "with #{bindings}\n"
      result += indented { emit(node.body) }
      result
    end

    def indent
      INDENT * @depth
    end

    def indented
      @depth += 1
      result = yield
      @depth -= 1
      result
    end
  end
end
