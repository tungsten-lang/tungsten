# Shared literal syntax for namespaced Bitfile declarations. Never evaluates code.
in Tungsten:Bit

+ BitfileDirective
  ro :namespace, :name, :arguments, :options, :line
  -> new(@namespace, @name, @arguments, @options, @line)

+ BitfileSyntax
  -> .digit?(b)
    b >= 48 && b <= 57

  -> .letter?(b)
    (b >= 65 && b <= 90) || (b >= 97 && b <= 122) || b == 95

  -> .identifier?(text)
    return false if text.size == 0 || !letter?(text.byte_at(0))
    i = 1
    while i < text.size
      b = text.byte_at(i)
      return false if !letter?(b) && !digit?(b) && b != 46 && b != 45
      i += 1
    true

  -> .number?(text)
    i = 0
    n = text.size
    i += 1 if i < n && (text.byte_at(i) == 43 || text.byte_at(i) == 45)
    first = i
    while i < n && digit?(text.byte_at(i))
      i += 1
    return false if i == first
    if i < n && text.byte_at(i) == 46
      i += 1
      first = i
      while i < n && digit?(text.byte_at(i))
        i += 1
      return false if i == first
    if i < n && (text.byte_at(i) == 101 || text.byte_at(i) == 69)
      i += 1
      i += 1 if i < n && (text.byte_at(i) == 43 || text.byte_at(i) == 45)
      first = i
      while i < n && digit?(text.byte_at(i))
        i += 1
      return false if i == first
    i == n

  -> .hex4(text)
    raise "incomplete Unicode escape" if text.size != 4
    value = 0
    i = 0
    while i < 4
      b = text.byte_at(i)
      digit = b >= 48 && b <= 57 ? b - 48 : b >= 65 && b <= 70 ? b - 55 : b >= 97 && b <= 102 ? b - 87 : -1
      raise "invalid Unicode escape" if digit < 0
      value = value * 16 + digit
      i += 1
    value

  -> .statements(text, namespaces)
    statements = []
    buffer = ""
    quote = nil
    escaped = false
    stack = []
    start = 0
    selected = nil
    number = 0
    text.split("\n").each ->(line)
      number += 1
      if buffer == ""
        selected = nil
        namespaces.each ->(namespace)
          selected = namespace if line.strip.starts_with?(namespace + ".")
      if buffer != "" || selected != nil
        start = number if buffer == ""
        clean = ""
        i = 0
        while i < line.size
          c = line.slice(i, 1)
          i += 1
          if quote != nil
            clean += c
            if escaped
              escaped = false
            elsif c == "\\"
              escaped = true
            elsif c == quote
              quote = nil
          elsif c == "\"" || c == "'"
            quote = c
            clean += c
          elsif c == "#"
            break
          else
            clean += c
            stack.push(c) if c == "\[" || c == "{"
            if c == "]" || c == "}"
              raise "line [number]: mismatched delimiter" if stack.size == 0
              opening = stack.pop
              raise "line [number]: mismatched delimiter" if (opening == "\[" && c != "]") || (opening == "{" && c != "}")
        buffer += " " + clean.strip
        if stack.size == 0 && quote == nil && !buffer.strip.ends_with?(",")
          statements.push([start, buffer.strip, selected])
          buffer = ""
      else
        statements.push([number, line, nil])
    raise "line [start]: incomplete Bitfile directive" if buffer != ""
    statements

+ BitfileLiterals
  -> new(text)
    @tokens = []
    @index = 0
    i = 0
    while i < text.size
      c = text.slice(i, 1)
      if " \n\r\t".include?(c)
        i += 1
      elsif c == "#"
        break
      elsif c == "\"" || c == "'"
        quote = c
        start = i
        i += 1
        escaped = false
        closed = false
        while i < text.size
          ch = text.slice(i, 1)
          i += 1
          if escaped
            escaped = false
          elsif ch == "\\"
            escaped = true
          elsif ch == quote
            closed = true
            break
        raise "unterminated Bitfile string" if !closed
        raw = text.slice(start, i - start)
        value = Bitfile.new().quoted(raw, quote == "\"")
        @tokens.push(["string", value])
      elsif "\[\]{},:".include?(c)
        @tokens.push(["punctuation", c])
        i += 1
      else
        start = i
        while i < text.size && !" \n\r\t\[\]{},:#".include?(text.slice(i, 1))
          i += 1
        raise "invalid Bitfile literal" if start == i
        raw = text.slice(start, i - start)
        number = BitfileSyntax.number?(raw)
        if number
          value = raw.include?(".") || raw.include?("e") || raw.include?("E") ? raw.to_f : raw.to_i
          raise "numbers must be finite" if value.to_f.nan? || value.to_f.infinite?
          @tokens.push(["number", value])
        else
          raise "invalid identifier \[raw]" if !BitfileSyntax.identifier?(raw)
          @tokens.push(["identifier", raw])

  -> peek(offset = 0)
    @index + offset < @tokens.size ? @tokens[@index + offset] : nil

  -> punctuation?(value)
    token = peek()
    token != nil && token[0] == "punctuation" && token[1] == value

  -> take(expected = nil)
    token = peek()
    raise "incomplete Bitfile directive" if token == nil
    @index += 1
    raise "expected [expected]" if expected != nil && token[1] != expected
    token

  -> key
    token = take()
    raise "expected a literal key" if token[0] != "string" && token[0] != "identifier"
    token[1]

  -> value(depth = 0)
    raise "Bitfile literal nesting exceeds 16" if depth > 16
    token = take()
    kind = token[0]
    v = token[1]
    return v if kind == "string" || kind == "number"
    return key() if v == ":"
    if v == "\["
      result = []
      while !punctuation?("]")
        result.push(value(depth + 1))
        break if !punctuation?(",")
        take(",")
      take("]")
      return result
    if v == "{"
      result = {}
      while !punctuation?("}")
        name = key()
        take(":")
        raise "duplicate key [name]" if result.has_key?(name)
        result[name] = value(depth + 1)
        break if !punctuation?(",")
        take(",")
      take("}")
      return result
    return true if v == "true"
    return false if v == "false"
    return nil if v == "nil"
    raise "values must be literals; executable expressions are forbidden"

  -> arguments
    positional = []
    options = {}
    while peek() != nil
      token = peek()
      next_token = peek(1)
      if next_token != nil && next_token[1] == ":" && (token[0] == "identifier" || token[0] == "string")
        name = key()
        take(":")
        raise "duplicate option [name]" if options.has_key?(name)
        options[name] = value()
      else
        positional.push(value())
      take(",") if peek() != nil
    [positional, options]
