# CSV — incremental comma-separated value parsing.
#
# CSVParser keeps its state between `feed` calls, so network/file adapters can
# pass bounded chunks without buffering the complete input. Rows are yielded as
# soon as a record terminator is known. The grammar follows the RFC 4180 field
# rules: quotes may wrap a complete field, doubled quotes escape one quote, and
# quoted fields may contain separators and CR/LF characters.

+ CSVParser
  -> new(separator = ",")
    if separator == nil || separator.size != 1 || separator == "\r" || separator == "\n" || separator == "\""
      raise "CSV separator must be one character other than quote, CR, or LF"
    @separator = separator
    sep_view = ccall("w_string_bytes_view", separator) ## u8[]
    @sep_byte = sep_view[0]
    @field = ""
    @row = []
    @state = :field_start
    @skip_lf = false
    @touched = false
    @line = 1
    @finished = false

  -> feed(chunk, &)
    raise "CSV parser is already finished" if @finished
    raise "CSV chunk must be a String" if type(chunk) != "String"

    s = chunk ## String
    view = ccall("w_string_bytes_view", s) ## u8[]
    n = view.size ## i64
    sep_b = @sep_byte ## i64
    i = 0
    while i < n
      b = view[i]
      if @skip_lf
        @skip_lf = false
        if b == 10
          i += 1
          next

      if @state == :quoted
        if b == 34
          @state = :after_quote
          @touched = true
          i += 1
          next
        run_start = i
        while i < n
          b2 = view[i]
          if b2 == 34
            break
          if b2 == 10
            @line += 1
          i += 1
        piece = s.slice(run_start, i - run_start)
        if @field == ""
          @field = piece
        else
          @field += piece
        @touched = true
        next

      if @state == :after_quote
        if b == 34
          @field += "\""
          @state = :quoted
          @touched = true
        elsif b == sep_b
          finish_field()
        elsif b == 13 || b == 10
          completed = finish_row()
          yield completed
          if b == 13
            @skip_lf = true
          @line += 1
        else
          parse_error("unexpected character after closing quote")
        i += 1
        next

      if b == sep_b
        finish_field()
        @touched = true
        i += 1
      elsif b == 13 || b == 10
        completed = finish_row()
        yield completed
        if b == 13
          @skip_lf = true
        @line += 1
        i += 1
      elsif b == 34
        if @state != :field_start
          parse_error("quote inside an unquoted field")
        @state = :quoted
        @touched = true
        i += 1
      else
        run_start = i
        i += 1
        if sep_b == 44
          while i + 4 <= n
            if view[i] > 44 && view[i + 1] > 44 && view[i + 2] > 44 && view[i + 3] > 44
              i += 4
            else
              break
        while i < n
          b2 = view[i]
          if b2 == sep_b || b2 == 10 || b2 == 13 || b2 == 34
            break
          i += 1
        piece = s.slice(run_start, i - run_start)
        if @field == "" && i < n
          term = view[i]
          if term == sep_b
            @row.push(piece)
            @state = :field_start
            @touched = true
            i += 1
            next
          if term == 10 || term == 13
            @row.push(piece)
            @state = :field_start
            completed = @row
            @row = []
            @touched = false
            yield completed
            if term == 13
              @skip_lf = true
            @line += 1
            i += 1
            next
        if @field == ""
          @field = piece
        else
          @field += piece
        @state = :unquoted
        @touched = true
    self

  -> finish(&)
    raise "CSV parser is already finished" if @finished
    @finished = true
    if @state == :quoted
      parse_error("unterminated quoted field")
    if @touched || @field != "" || @row.size > 0
      completed = finish_row()
      yield completed
    self

  -> finished?
    @finished

  -> finish_field
    @row.push(@field)
    @field = ""
    @state = :field_start

  -> finish_row
    finish_field()
    completed = @row
    @row = []
    @touched = false
    completed

  -> parse_error(message)
    raise "CSV parse error at line " + @line.to_s + ": " + message

# CSV facade — whole-string convenience and chunk-stream adapters.
+ CSV
  -> .each_row(source, separator = ",", &)
    parser = CSVParser.new(separator)
    parser.feed(source) -> (row)
      yield row
    parser.finish() -> (row)
      yield row
    nil

  -> .parse(source, separator = ",")
    if type(source) == "String" && separator != nil && separator.size == 1 && separator != "\r" && separator != "\n" && separator != "\""
      s = source ## String
      if !s.include?("\"")
        view = ccall("w_string_bytes_view", s) ## u8[]
        n = view.size ## i64
        if n == 0
          return []
        ptr = ccall_nobox("w_u8_live_data_ptr", view) ## i64
        sep_b = 44 ## i64
        if separator != ","
          sep_view = ccall("w_string_bytes_view", separator ## String) ## u8[]
          sep_b = sep_view[0] ## i64
        rows = []
        row = []
        cols = 0 ## i64
        col_i = 0 ## i64
        field_start = 0 ## i64
        touched = false
        i = 0 ## i64
        while i < n
          if sep_b == 44
            while i + 4 <= n
              if raw_load_u8(ptr, i) > 44 && raw_load_u8(ptr, i + 1) > 44 && raw_load_u8(ptr, i + 2) > 44 && raw_load_u8(ptr, i + 3) > 44
                i += 4
              else
                break
          while i < n
            b = raw_load_u8(ptr, i) ## i64
            if b == sep_b || b == 10 || b == 13
              break
            i += 1
          if i >= n
            break
          b = raw_load_u8(ptr, i) ## i64
          val = s.slice(field_start, i - field_start)
          if col_i < cols
            row[col_i] = val
          else
            row.push(val)
          col_i += 1
          if b == sep_b
            touched = true
            i += 1
          else
            if col_i < cols
              row = row.take(col_i)
            elsif cols == 0
              cols = col_i
            rows.push(row)
            col_i = 0
            touched = false
            if b == 13 && i + 1 < n && raw_load_u8(ptr, i + 1) == 10
              i += 2
            else
              i += 1
            if i < n && cols > 0
              row = Array.new(cols)
            else
              row = []
          field_start = i
        if field_start < n || touched || col_i > 0
          val = s.slice(field_start, n - field_start)
          if col_i < cols
            row[col_i] = val
          else
            row.push(val)
          col_i += 1
          if col_i < cols
            row = row.take(col_i)
          rows.push(row)
        return rows
    rows = []
    CSV.each_row(source, separator) -> (row)
      rows.push(row)
    rows

  # Feed an Enumerable of bounded String chunks through one parser. This is
  # the adapter used by streaming transports and avoids joining the chunks.
  -> .each_chunked(chunks, separator = ",", &)
    parser = CSVParser.new(separator)
    chunks.each -> (chunk)
      parser.feed(chunk) -> (row)
        yield row
    parser.finish() -> (row)
      yield row
    nil

  -> .parse_chunks(chunks, separator = ",")
    rows = []
    CSV.each_chunked(chunks, separator) -> (row)
      rows.push(row)
    rows
