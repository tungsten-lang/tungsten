use strscan

$debug = false

in Tungsten

+ Lexer < StringScanner
  rw :file

  -> new(code)
    debug_code if $debug

    @token = Token.new

    @indent = 0

    @indebt = 0
    @dedebt = 0

    @row = 1

    super clean(code)

    handle_indentation

  -> debug_code
    <<
    <<
    << code
    <<
    <<

  -> debug_token
    if @token.type == :NL
      <<
    elsif @tokekn.type == :INDENT
      <- '  ' * (@indent + 1)
      <- '  '
    else
      <- @token.type.to_s + ' '

  -> clean(code)
    code.delete! BOM, CR, TRAILING_SPACE

  -> handle_indentation
    # @todo check this regex (?=\$) looks wrong
    if check /^(?=\S)|^(?=\$)/
      @dedebt ++ @indent
      return

    scan /^(?:\s\s)+(?=\S)/

    if matched
      diff = (matched.size / 2) - @indent

      if diff > 0
        @indebt = diff
      elsif diff < 0
        @dedebt = diff.abs

    @cols = 0

  -> error(msg)
    raise Error.new("syntax on line [@row]: [msg]")

  -> scan(regex)
    @cols = match.size if (match = super)

    match

  -> token(type, value = nil)
    @token.assign args
