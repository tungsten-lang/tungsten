# frozen_string_literal: true

def stage0_trim(text)
  text.strip
end

def stage0_string_literal?(text)
  text.start_with?("\"") && text.end_with?("\"")
end

def stage0_unquote(text)
  text[1, text.length - 2]
end

def stage0_atom_value(expr, start_pos, end_pos, x_value, y_value, z_value, a_value, b_value)
  first = expr.getbyte(start_pos)
  if first >= 48 && first <= 57
    value = 0
    i = start_pos
    while i < end_pos
      b = expr.getbyte(i)
      value = value * 10 + b - 48 if b >= 48 && b <= 57
      i += 1
    end
    value
  elsif first == 120
    x_value
  elsif first == 121
    y_value
  elsif first == 122
    z_value
  elsif first == 97
    a_value
  elsif first == 98
    b_value
  else
    0
  end
end

def stage0_eval_add_call(text, x_value, y_value, z_value)
  inner = text[4, text.length - 5]
  parts = inner.split(",")
  left = stage0_eval_int(parts[0], x_value, y_value, z_value, 0, 0)
  right = stage0_eval_int(parts[1], x_value, y_value, z_value, 0, 0)
  left + right
end

def stage0_eval_int(expr, x_value, y_value, z_value, a_value, b_value)
  text = stage0_trim(expr)
  return stage0_eval_add_call(text, x_value, y_value, z_value) if text.start_with?("add(")

  pos = 0
  op = 43
  value = 0

  while pos < text.length
    pos += 1 while pos < text.length && text.getbyte(pos) == 32
    start_pos = pos
    while pos < text.length
      b = text.getbyte(pos)
      break if b == 32 || b == 43 || b == 45 || b == 42 || b == 47 || b == 37

      pos += 1
    end
    rhs = stage0_atom_value(text, start_pos, pos, x_value, y_value, z_value, a_value, b_value)
    if op == 43
      value += rhs
    elsif op == 45
      value -= rhs
    elsif op == 42
      value *= rhs
    elsif op == 47
      value /= rhs
    elsif op == 37
      value %= rhs
    end

    pos += 1 while pos < text.length && text.getbyte(pos) == 32
    if pos < text.length
      op = text.getbyte(pos)
      pos += 1
    end
  end
  value
end

def stage0_print_expr(expr, x_value, y_value, z_value)
  text = stage0_trim(expr)
  if stage0_string_literal?(text)
    puts stage0_unquote(text)
  else
    puts stage0_eval_int(text, x_value, y_value, z_value, 0, 0)
  end
end

def stage0_condition_true?(condition, x_value, y_value, z_value)
  text = stage0_trim(condition)
  if text.include?(">")
    parts = text.split(">")
    left = stage0_eval_int(parts[0], x_value, y_value, z_value, 0, 0)
    right = stage0_eval_int(parts[1], x_value, y_value, z_value, 0, 0)
    left > right
  elsif text.include?("<")
    parts = text.split("<")
    left = stage0_eval_int(parts[0], x_value, y_value, z_value, 0, 0)
    right = stage0_eval_int(parts[1], x_value, y_value, z_value, 0, 0)
    left < right
  else
    stage0_eval_int(text, x_value, y_value, z_value, 0, 0) != 0
  end
end

def tungsten_stage0_run(source)
  x_value = 0
  y_value = 0
  z_value = 0
  lines = source.split("\n")
  i = 0
  while i < lines.length
    line = stage0_trim(lines[i])
    if line.start_with?("-> add(")
      i += 1
    elsif line.start_with?("if ")
      condition = ""
      condition = line[3, line.length - 3]
      then_line = stage0_trim(lines[i + 1])
      else_line = ""
      if i + 3 < lines.length && stage0_trim(lines[i + 2]) == "else"
        else_line = stage0_trim(lines[i + 3])
      end
      if stage0_condition_true?(condition, x_value, y_value, z_value)
        if then_line.start_with?("<< ")
          text = ""
          text = then_line[3, then_line.length - 3]
          stage0_print_expr(text, x_value, y_value, z_value)
        end
      elsif else_line.start_with?("<< ")
        text = ""
        text = else_line[3, else_line.length - 3]
        stage0_print_expr(text, x_value, y_value, z_value)
      end
      i += 3
    elsif line.start_with?("while ")
      condition = ""
      condition = line[6, line.length - 6]
      body_line = stage0_trim(lines[i + 1])
      guard = 0
      while stage0_condition_true?(condition, x_value, y_value, z_value) && guard < 100000
        if body_line.include?("+=")
          parts = body_line.split("+=")
          name = stage0_trim(parts[0])
          expr = stage0_trim(parts[1])
          if name == "x"
            x_value += stage0_eval_int(expr, x_value, y_value, z_value, 0, 0)
          elsif name == "y"
            y_value += stage0_eval_int(expr, x_value, y_value, z_value, 0, 0)
          elsif name == "z"
            z_value += stage0_eval_int(expr, x_value, y_value, z_value, 0, 0)
          end
        end
        guard += 1
      end
      i += 1
    elsif line.start_with?("<< ")
      text = ""
      text = line[3, line.length - 3]
      stage0_print_expr(text, x_value, y_value, z_value)
    elsif line.include?("+=")
      parts = line.split("+=")
      name = stage0_trim(parts[0])
      expr = stage0_trim(parts[1])
      if name == "x"
        x_value += stage0_eval_int(expr, x_value, y_value, z_value, 0, 0)
      elsif name == "y"
        y_value += stage0_eval_int(expr, x_value, y_value, z_value, 0, 0)
      elsif name == "z"
        z_value += stage0_eval_int(expr, x_value, y_value, z_value, 0, 0)
      end
    elsif line.include?("=")
      parts = line.split("=")
      name = stage0_trim(parts[0])
      expr = stage0_trim(parts[1])
      if name == "x"
        x_value = stage0_eval_int(expr, x_value, y_value, z_value, 0, 0)
      elsif name == "y"
        y_value = stage0_eval_int(expr, x_value, y_value, z_value, 0, 0)
      elsif name == "z"
        z_value = stage0_eval_int(expr, x_value, y_value, z_value, 0, 0)
      end
    end
    i += 1
  end
end

if ARGV.length == 0
  puts "usage: tungsten-stage0 FILE.w [args...]"
  exit 64
end

tungsten_stage0_run(File.read(ARGV[0]))
