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

    i = 0
    while i < chunk.size
      ch = chunk[i]
      if @skip_lf
        @skip_lf = false
        if ch == "\n"
          i += 1
          next

      if @state == :quoted
        if ch == "\""
          @state = :after_quote
        else
          @field += ch
          if ch == "\n"
            @line += 1
        @touched = true
        i += 1
        next

      if @state == :after_quote
        if ch == "\""
          @field += "\""
          @state = :quoted
          @touched = true
        elsif ch == @separator
          finish_field()
        elsif ch == "\r" || ch == "\n"
          completed = finish_row()
          yield completed
          if ch == "\r"
            @skip_lf = true
          @line += 1
        else
          parse_error("unexpected character after closing quote")
        i += 1
        next

      if ch == @separator
        finish_field()
        @touched = true
      elsif ch == "\r" || ch == "\n"
        completed = finish_row()
        yield completed
        if ch == "\r"
          @skip_lf = true
        @line += 1
      elsif ch == "\""
        if @state != :field_start
          parse_error("quote inside an unquoted field")
        @state = :quoted
        @touched = true
      else
        @field += ch
        @state = :unquoted
        @touched = true
      i += 1
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
