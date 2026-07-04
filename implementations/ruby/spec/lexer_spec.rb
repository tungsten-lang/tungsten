# rubocop:disable Layout/ArrayAlignment
# rubocop:disable Layout/FirstArrayElementIndentation
# rubocop:disable Layout/LineLength
# rubocop:disable Layout/SpaceInsideArrayPercentLiteral

RSpec.shared_examples "a Tungsten lexer" do
  class << self
    def it_lexes(string, type, value=nil)
      it "lexes #{string}" do
        lexer = described_class.new(string)
        token = lexer.next_token

        expect(token.type).to  eq(type)
        expect(token.value).to eq(value)
      end
    end

    def it_does_not_lex(name, code, type=nil, value=nil)
      it "does not lex #{name}" do
        lexer = described_class.new(code)

        # 100 is arbitrary, but stops infinite loops
        expect { 100.times { lexer.next_token } }.to raise_error(Tungsten::Error)
      end
    end

    def it_lexes_all(name, string, *types)
      it "lexes #{name}" do
        lexer = described_class.new(string)

        while token = lexer.next_token
          break if token.type == :EOF

          expect(token.type).to eq(types.shift)
        end

        expect(types).to be_empty
      end
    end

    def lexes(name, sym)
      define_singleton_method(:"it_lexes_#{name}") do |*args|
        args = args.first if args.first.is_a? Array
        args.each do |arg|
          it_lexes arg, sym, arg
        end
      end

      define_singleton_method(:"it_does_not_lex_#{name}") do |*args|
        args = args.first if args.first.is_a? Array
        args.each do |arg|
          it_does_not_lex name, arg, sym, arg
        end
      end
    end

    def it_lexes_keywords(*args)
      args = args.first if args.first.is_a? Array
      args.each do |arg|
        it_lexes arg, :KEYWORD, arg.to_sym
      end
    end

    def it_lexes_error(name, *args)
      args = args.first if args.first.is_a? Array
      args.each do |arg|
        it "errors on #{name}: #{arg}" do
          lexer = described_class.new(arg)
          expect { lexer.next_token }.to raise_error(Tungsten::Error)
        end
      end
    end

    def it_lexes_operators(*args)
      args = args.first if args.first.is_a? Array
      args.each do |arg|
        it_lexes arg, arg.to_sym
      end
    end

    def it_lexes_chars(*args)
      args = args.first if args.first.is_a? Array
      args.each do |arg|
        it_lexes arg, :CODEPOINT, [arg.gsub("U+", "").to_i(16)].pack('U')
      end
    end

    def it_lexes_currencies(*args)
      args = args.first if args.first.is_a? Array
      args.each do |arg|
        match = arg.match(Tungsten::Lexer::CURRENCY)
        it_lexes arg, :CURRENCY, [match[:amount], match[:prefix], match[:suffix]]
      end
    end

    def it_does_not_lex_chars(*args)
      args = args.first if args.first.is_a? Array
      args.each do |arg|
        it_does_not_lex "chars", arg, :CODEPOINT, [arg.gsub("U+", "").to_i(16)].pack('U')
      end
    end
  end

  lexes "class_names",            :NAME
  lexes "constants",              :CONSTANT
  lexes "identifiers",            :ID
  lexes "identifiers_with_arity", :ID_WITH_ARITY
  lexes "ivars",                  :IVAR
  lexes "globals",                :GLOBAL
  lexes "positions",              :PARG

  lexes "rationals",              :RATIONAL
  lexes "ints",                   :INT
  lexes "floats",                 :FLOAT
  lexes "decimals",               :DECIMAL

  lexes "ipv4",                   :IP4
  lexes "ipv6",                   :IP6
  lexes "cidr4",                  :CIDR4
  lexes "cidr6",                  :CIDR6
  lexes "mac",                    :MAC

  lexes "uuids",                  :UUID

  lexes "dates",                  :DATE
  lexes "datetimes",              :DATETIME
  lexes "durations",              :DURATION
  lexes "months",                 :MONTH
  lexes "weeks",                  :WEEK
  lexes "times",                  :TIME

  lexes "true",                   :TRUE
  lexes "false",                  :FALSE
  lexes "nil",                    :NIL


  it_lexes_all "comment and method call", "# comment\nmethod", *%i[NL ID]

  it "lexes comment at the end" do
    lexer = described_class.new "# comment"

    token = lexer.next_token
    expect(token.type).to eq(:EOF)
  end

  it_lexes_all "inline comment after expression", "x = 1 # note\ny = 2", *%i[ID SP = SP INT NL ID SP = SP INT]
  it_lexes_all "line-leading double-hash type hint and method call", "## type: Int\nmethod", *%i[TYPE_HINT NL ID]
  it_lexes_all "bare line-leading double-hash (empty type hint)", "##\nmethod", *%i[NL ID]

  it "does not treat # after code without a leading space as a comment" do
    lexer = described_class.new("x = 1# note\n")
    expect { 100.times { lexer.next_token } }.to raise_error(Tungsten::Error)
  end

  it "treats ## after code as inline type hint" do
    lexer = described_class.new("x = 1 ## i128\n")
    types = []
    100.times do
      tok = lexer.next_token
      break if tok.type == :EOF
      types << tok.type
    end
    expect(types).to include(:TYPE_HINT)
  end

  string = <<~END
    if condition
      puts true
    else
      puts false
  END

  it_lexes_all "single indent / dedent", string, *%i[KEYWORD SP ID         NL
                                                     INDENT  ID SP TRUE    NL
                                                     DEDENT        KEYWORD NL
                                                     INDENT  ID SP FALSE   NL
                                                     DEDENT]


  string = <<~END
    if
      while
        puts
    else
      puts
  END

  it_lexes_all "indents and dedents", string, *%i[       KEYWORD        NL
                                                  INDENT KEYWORD        NL
                                                  INDENT ID             NL
                                                  DEDENT DEDENT KEYWORD NL
                                                  INDENT ID             NL
                                                  DEDENT]

  string = "+ Int"
  it_lexes_all "a class", string, *%i[CLASS SP NAME]

  string = "+ Int < Number"
  it_lexes_all "a class w/ inheritance", string, *%i[CLASS SP NAME SP < SP NAME]

  string = <<~END
    in Tungsten

    + Int < Number
  END
  it_lexes_all "a class with module", string, *%i[KEYWORD SP NAME NL
                                                  CLASS   SP NAME SP < SP NAME NL]
  string = <<~END
    in Tungsten

    + Int < Number
      -> new
  END
  it_lexes_all "a class with method", string, *%i[KEYWORD SP NAME NL
                                                  CLASS   SP NAME SP < SP NAME NL
                                                  INDENT -> SP ID NL
                                                  DEDENT]

  it_lexes " ",  :SP
  it_lexes_all "multiple spaces", "  ", :SP

  it_lexes "\n",   :NL, 1
  it_lexes "\n\n", :NL, 2

  it_lexes "\uFEFF1", :INT, "1"

  # trailing space
  it_lexes " \n",   :NL, 1
  it_lexes " \n\n", :NL, 2

  it_does_not_lex "\\t", "1 \t + 1"
  it_does_not_lex "\\r", "1 \r + 1"
  it_does_not_lex "\\f", "1 \f + 1"

  it_does_not_lex "BOM", "1 + \uFEFF"

  it_lexes "nil",  :NIL
  it_lexes "nil ", :NIL
  it_lexes "nil.", :NIL
  it_lexes "nil)", :NIL

  it_lexes_all "nil? calls", "1.nil?", *%i[INT . ID]
  it_lexes_all "nil! calls", "1.nil!", *%i[INT . ID]

  it_lexes_all "line endings", "2   \n\n", *%i[INT NL]

  it_lexes_all "trailing spaces", "return true  \n", *%i[KEYWORD SP TRUE NL]

  it_lexes_all "method definitions", "  -> foo", *%i[INDENT -> SP ID DEDENT]

  it_lexes_all "method call",     "obj.method",   *%i[ID  . ID]
  it_lexes_all "method on int",   "10.to_s",      *%i[INT . ID]

  it_lexes_all "class method",    "Math.pow",     *%i[NAME . ID]
  it_lexes_all "constant method", "DEBUG.to_b",   *%i[CONSTANT . ID]

  it_lexes_all "gvar method",     "$debug.to_b",  *%i[GLOBAL . ID]
  it_lexes_all "ivar method",     "@name.upcase", *%i[IVAR . ID]

  it_lexes_all "math expression", "x = 2 * 6 + 4 / 2", *%i[ID SP = SP INT SP * SP INT SP + SP INT SP / SP INT]

  it_lexes_true
  it_lexes_false

  it_lexes_nil

  it "lexes hex color literals" do
    examples = {
      "#f00" => [255, 0, 0, 255],
      "#f008" => [255, 0, 0, 136],
      "#ff0000" => [255, 0, 0, 255],
      "#ff000080" => [255, 0, 0, 128],
    }

    examples.each do |source, value|
      lexer = described_class.new(source)
      token = lexer.next_token

      expect(token.type).to eq(:COLOR)
      expect(token.value).to eq(value)
    end
  end

  it_lexes_operators %w[
    = == ===
    ! != !==
    < <= << <<= <=>
    > >= >> >>=
    + += +@ ++
    - -= -@ --
    ~ =~ ~@ ~~ !~
    * *= ** **=
    / /= // //=
    % %= %% %%=
    ^ ^=
    | |> |= || ||=
    & &= && &&=
    ~ ~=

    ( )
   <( )>
   <"
   <- -> =>
   <[ ]>
    [ ] [] []=
    { }

    ; , . .. ...

    ? :

    $ @
  ]

  # `"> ` is valid only in operator position (after a value); standalone, the
  # leading `"` correctly opens a string (see codepoint_lexer.rb:435). Exercise
  # it after a value rather than via the standalone it_lexes_operators list.
  it_lexes_all(%q{"> after a value}, %q{a">}, :ID, :'">')

  it_lexes_keywords %w[
    alias
    break
    case continue
    else elsif
    if in
    next
    raise redo rescue retry return
    super
    trait
    unless until use
    when while
    yield
  ]

  it_lexes "%w[", :WORD_ARRAY
  it_lexes "%i[", :SYMBOL_ARRAY

  it_lexes "__FILE__", :MAGIC_FILE
  it_lexes "__LINE__", :MAGIC_LINE
  it_lexes "__DIR__",  :MAGIC_DIR

  it_lexes_class_names %w[
    Base64
    Sha256
    Int
    Float
    CodePoint
  ]

  it_lexes_constants %w[
    VERBOSE
    MORE_THAN_ONE_WORD
    WORD12
    SHA256
  ]

  it_lexes_identifiers %w[
    name
    name1
    name2
    name_with_underscores
    name_with_1
    name?
    name!
    name=

    x
    y
    z

    x1
    x2
  ]

  it_lexes_identifiers_with_arity %w[
    name=/1

    name/0
    name/1
    name/*

    max/2
  ]

  # @todo ==/2 <=>/2 -@/1 +@/1 ~@/1 []=/2 []/1

  it_lexes_ivars %w[
    @x
    @y
    @z

    @name
    @name1
    @name2
    @name_with_underscores
    @name_with_1
  ]

  it_lexes_globals %w[
    $x $_x

    $verbose
    $debug
    $global_with_underscores
    $global_with_digit_1
    $global1
  ]

  it "lexes regex captures after a regex literal on the same line" do
    lexer = described_class.new("/(.)/ => $1.to_sym")
    tokens = lexer.tokens.map { |token| [token.type, token.value] }

    expect(tokens).to include([:REGEX_CAPTURE, "1"])
  end

  # no double__underscores

  it_lexes_positions %w[
    @1
    @2
    @10
  ]

  it_lexes "U+221E", :CODEPOINT, "∞"

  it_lexes_chars %w[
    U+93A2
    U+94A8

    U+2764

    U+1F37F
    U+1F47E
    U+1F913
    U+1F916

    U+0009
    U+000A
    U+000D
    U+FEFF

    U+10000
    U+11000

    U+1F525

    U+10FFFD
  ]

  it_lexes "/^--(.+)$/", :REGEX, ["^--(.+)$", ""]
  it_lexes "/foo/imx",   :REGEX, ["foo", "imx"]

  it_does_not_lex_chars %w[
    U+110000

    U+0FFFFF
    U+00FFFE
    U+00FFFF

    U+010000
    U+011000
    U+01FFFF
    U+0FFFFF

    U+D800
    U+DBFF
    U+DC00
    U+DFFF

    U+FDD0
    U+FDD1
    U+FDD2
    U+FDD3
    U+FDD4
    U+FDD5
    U+FDD6
    U+FDD7
    U+FDD8
    U+FDD9
    U+FDDA
    U+FDDB
    U+FDDC
    U+FDDD
    U+FDDE
    U+FDDF
    U+FDE0
    U+FDE1
    U+FDE2
    U+FDE3
    U+FDE4
    U+FDE5
    U+FDE6
    U+FDE7
    U+FDE8
    U+FDE9
    U+FDEA
    U+FDEB
    U+FDEC
    U+FDED
    U+FDEE
    U+FDEF

    U+FFFE
    U+FFFF
    U+1FFFE
    U+1FFFF
    U+2FFFE
    U+2FFFF
    U+3FFFE
    U+3FFFF
    U+4FFFE
    U+4FFFF
    U+5FFFE
    U+5FFFF
    U+6FFFE
    U+6FFFF
    U+7FFFE
    U+7FFFF
    U+8FFFE
    U+8FFFF
    U+9FFFE
    U+9FFFF
    U+AFFFE
    U+AFFFF
    U+BFFFE
    U+BFFFF
    U+CFFFE
    U+CFFFF
    U+DFFFE
    U+DFFFF
    U+EFFFE
    U+EFFFF
    U+FFFFE
    U+FFFFF
    U+10FFFE
    U+10FFFF
  ]

  it_lexes_dates %w[
    2019-01-01
    2019-08-31
    2019-12-25
  ]

  it_lexes_weeks %w[
    2021-W01
    2021-W02
    2021-W03
    2021-W04
    2021-W05
    2021-W06
    2021-W07
    2021-W08
    2021-W09
    2021-W10
    2021-W11
    2021-W12
    2021-W13
    2021-W14
    2021-W15
    2021-W16
    2021-W17
    2021-W18
    2021-W19
    2021-W20
    2021-W21
    2021-W22
    2021-W23
    2021-W24
    2021-W25
    2021-W26
    2021-W27
    2021-W28
    2021-W29
    2021-W30
    2021-W31
    2021-W32
    2021-W33
    2021-W34
    2021-W35
    2021-W36
    2021-W37
    2021-W38
    2021-W39
    2021-W40
    2021-W41
    2021-W42
    2021-W43
    2021-W44
    2021-W45
    2021-W46
    2021-W47
    2021-W48
    2021-W49
    2021-W50
    2021-W51
    2021-W52

    2020-W53
  ]

  it_lexes_error "invalid week", %w[
    2021-W0
    2021-W53
    2021-W100
  ]

  # 2021 does not have 53 weeks, 2020 does

  it_lexes_months %w[
    2019-01
    2019-02
    2019-03
    2019-04
    2019-05
    2019-06
    2019-07
    2019-08
    2019-09
    2019-10
    2019-11
    2019-12
  ]


  it_lexes_times %w[
    00:00
    11:59
    24:00

    23:59:59
    23:59:60

    00:00:00.1
    00:00:00.01
    00:00:00.001
    00:00:00.100
    00:00:00.10

    00:00+02
    11:59+02
    24:00+02

    23:59:59+02
    23:59:60+02

    00:00:00.1+02
    00:00:00.01+02
    00:00:00.001+02

    00:00-07:00
    11:59-07:00
    24:00-07:00

    23:59:59-07:00
    23:59:60-07:00

    00:00:00.1-07:00
    00:00:00.01-07:00
    00:00:00.001-07:00
    00:00:00.100-07:00
    00:00:00.10-07:00

    00:00Z
    11:59Z
    24:00Z

    23:59:59Z
    23:59:60Z

    00:00:00.1Z
    00:00:00.01Z
    00:00:00.001Z
    00:00:00.10Z
    00:00:00.100Z
  ]

  it_lexes_durations %w[
    2h30m
    1d12h
    5m30s
    1h30m45s
    1y6mo
    2w3d
    1h500ms
    3s100ms
    10m5s200ms
    1d2h30m15s
    P1Y
    P1Y2M
    P1Y2M3D
    P3Y6M
    P1W
    P1DT2H
    PT1H30M
    PT1H
    PT30M
    PT45S
    PT1H30M15S
    P1Y2M3DT4H5M6S
    PT1.5S
    PT30.5M
    PT1.5H
    P1.5Y
    P1Y2.5M
    P1Y2M3.5D
    P4W
    P2.5W
  ]

  it_does_not_lex "duration with wrong order", "30s2h"

  it_lexes_datetimes %w[
    2019-08-31T00:00Z
    2019-08-31T00:00:00Z
    2019-08-31T00:00:00.0Z
    2019-08-31T00:00:00.00Z
    2019-08-31T00:00:00.000Z
    2019-08-31T00:00:00.000+07:00
    2019-08-31T00:00:00.000-07:00
    2019-08-31T00:00:00.000−07:00
    2019-08-31T00:00:00.000+0700
    2019-08-31T00:00:00.000-0700
    2019-08-31T00:00:00.000−0700
    2019-08-31T00:00:00.000+07
    2019-08-31T00:00:00.000-07
    2019-08-31T00:00:00.000−07
  ]

  it_lexes_floats %w[
   -~0.0
   −~0.0
   +~0.0
    ~0.0
    ~0.1
    ~1.0
    ~1.23
    ~1.0e0
    ~1.0e1
    ~1.0e+1
    ~1.0e-1
    ~1.0e10
    ~1.100_000
    ~0.000_1
    ~1_000.0
  ]

  it_lexes_rationals %w[
    +22/7 -22/7 −22/7

     0⁄0  1⁄1  2⁄2  3⁄3  4⁄4  5⁄5  6⁄6  7⁄7  8⁄8  9⁄9  10⁄10
     0/0  1/0
     0/1  1/1
     0/2  1/2  2/2
     0/3  1/3  2/3  3/3
     0/4  1/4  2/4  3/4  4/4
     0/5  1/5  2/5  3/5  4/5  5/5
     0/6  1/6  2/6  3/6  4/6  5/6  6/6
     0/7  1/7  2/7  3/7  4/7  5/7  6/7  7/7
     0/8  1/8  2/8  3/8  4/8  5/8  6/8  7/8  8/8
     0/9  1/9  2/9  3/9  4/9  5/9  6/9  7/9  8/9  9/9
     0/10 1/10 2/10 3/10 4/10 5/10 6/10 7/10 8/10 9/10 10/10

                   1_0000_0000/1
                  1_00_00_000/1
                    1_00_000/1

                10_000_000/1
                1_000_000/1
                100_000/1
                10_000/1
                1_000/1
                100/1
                10/1
                1/10
               1/100
             1/1_000
            1/10_000
           1/100_000
         1/1_000_000
        1/10_000_000

      1/1_00_000
     1/1_00_00_000
    1/1000_0000_0000
  ]

  # previously had   00 01 02 03 04 05 06 07 08 09 10 11 12

  it_lexes_ints %w[
    0
   +0
   -0

   +1
   +1_000
   +1_000_000

   +1_00_000
   +1_00_00_000

   -1
   -1_000
   -1_000_000

   -1_00_000
   -1_00_00_000

    0 1 2 3 4 5 6 7 8 9 10 11 12

    0b0
    0b1
    0b00
    0b01
    0b10
    0b11

    0b0000
    0b0001
    0b0010
    0b0100
    0b1000
    0b1111

    0b000_001_010_100
    0b1010100_1110101_1101110_1100111_1110011_1110100_1100101_1101110

    0o000
    0o655
    0o755
    0o777

   +0d1
   -0d1
    0d1
    0d10
    0d100

   +0x00
   -0x00

    0x00 0x01 0x02 0x03 0x04 0x05 0x06 0x07 0x08 0x09

    0x0a 0x0b 0x0c 0x0d 0x0e 0x0f 0xff
    0x0A 0x0B 0x0C 0x0D 0x0E 0x0F
    0x10

    0xdeadbeef 0xdead_beef
    0xDEADBEEF 0xDEAD_BEEF

    0v00 0v01 0v02 0v03 0v04 0v05 0v06 0v07 0v08 0v09

    0v0a 0v0b 0v0c 0v0d 0v0e 0v0f 0v0g 0v0h 0v0i 0v0j
    0v0A 0v0B 0v0C 0v0D 0v0E 0v0F 0v0G 0v0H 0v0I 0v0J

    0v10

    0vjj
    0vJJ

    0r2-10 0r2-0 0r2-1
    0r3-10 0r3-0 0r3-1 0r3-2
    0r4-10 0r4-0 0r4-1 0r4-2 0r4-3
    0r5-10 0r5-0 0r5-1 0r5-2 0r5-3 0r5-4
    0r6-10 0r6-0 0r6-1 0r6-2 0r6-3 0r6-4 0r6-5
    0r7-10 0r7-0 0r7-1 0r7-2 0r7-3 0r7-4 0r7-5 0r7-6
    0r8-10 0r8-0 0r8-1 0r8-2 0r8-3 0r8-4 0r8-5 0r8-6 0r8-7
    0r9-10 0r9-0 0r9-1 0r9-2 0r9-3 0r9-4 0r9-5 0r9-6 0r9-7 0r9-8

    0r10-10 0r10-0 0r10-1 0r10-2 0r10-3 0r10-4 0r10-5 0r10-6 0r10-7 0r10-8 0r10-9
    0r11-10 0r11-0 0r11-1 0r11-2 0r11-3 0r11-4 0r11-5 0r11-6 0r11-7 0r11-8 0r11-9
    0r11-0a 0r11-aa

    0r16-0000
    0r16-ffff
    0r16-deadbeef
    0r16-DEADBEEF
    0b36-ZIK0ZJ
    0b36-1Y2P0IJ32E8E7
    0b36-WIKIPEDIA

    0b58-123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz
    0b58-123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz
    0b58-123456789abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ

    0b60-abc

    0b64-jA0ECgMCl9ViayBOZkZg0kkBDqU+4ofR+bJDXd+cpfAQCk30pFcK4QmtFXYivhqyN8WrBUN8ala9bJ8ON2+COaB1ls+Pr9ohpiWSQLlC6t6/fQLSsHFLCJq5=GH0r
    0b64-VHVuZ3N0ZW4=
  ]

  it_lexes_decimals %w[
     0.0
    +0.0
    -0.0
    −0.0

    +1.00
    +1_000.00
    +1_00_000.00
    +1_00_00_000.00

    -1.00
    -1_000.00
    -1_00_000.00
    -1_00_00_000.00

    +1.0_00_000

    273.16K

    48°57′54.8″N
    120°08′16.6″W

    48°57'54.8"N
    120°08'16.6"W

    0r60-0;2,24
    0r60-0;8,34,17
    0r60-0;5,27,16,21,49
    0r60-0;10
    0r60-0;10,40
    0r60-0;12
    0r60-1;24,51,10
    0r60-1;24,51,10,7,46,6,4,44
    0r60-3;8,30
    0r60-6;16,59,28,1,34,51,46,14,50
    0r60-6;16,59,28,1,34,51,46,14,49,55,12,35
    0r60-6,5;14,44,51

    16′52″30‴
    16'52"
  ]

  it_lexes_ipv4 %w[
    0.0.0.0
    10.0.0.1
    127.0.0.1
    255.255.255.255
  ]

  it_lexes_ipv6 %w[
    1::
    1::8
    1::7:8
    1::6:7:8
    1::5:6:7:8
    1::4:5:6:7:8
    1::3:4:5:6:7:8

    ::2:3:4:5:6:7:8
    1::3:4:5:6:7:8
    1:2::4:5:6:7:8
    1:2:3::5:6:7:8
    1:2:3:4::6:7:8
    1:2:3:4:5::7:8
    1:2:3:4:5:6::8
    1:2:3:4:5:6:7::

    ::8
    1::8
    1:2::8
    1:2:3::8
    1:2:3:4::8
    1:2:3:4:5::8
    1:2:3:4:5:6::8

    fc00::

    fe80::7:8%eth0
    fe80::7:8%1

    FE80::7:8%eth0
    FE80::7:8%1

    ff00::
    ff01::
    ff02::
    ff03::
    ff04::
    ff05::
    ff08::
    ff0e::
    ff0f::

    ff01::1
    ff01::2
    ff02::5
    ff02::6
    ff02::9
    ff02::a
    ff02::d
    ff02::1a
    ff02::fb
    ff02::101
    ff02::1:1
    ff02::1:2
    ff02::1:3
    ff05::1:3

    ::255.255.255.255

    ::ffff:255.255.255.255
    ::FFFF:255.255.255.255

    ::ffff:0:0
    ::ffff:0:0:0

    ::ffff:0:255.255.255.255
    ::FFFF:0:255.255.255.255

    64:ff9b::

    0100::

    2001:db8:3:4::192.0.2.33

    2001:0db8:0000:0000:0000:ff00:0042:8329
    2001:db8:0:0:0:ff00:42:8329
    2001:db8::ff00:42:8329

    2002::
  ]

  it_lexes_cidr4 %w[
     0.0.0.0/8
    10.0.0.0/8
    62.0.0.0/8

    100.64.0.0/10

    127.0.0.0/8

    169.254.0.0/16

    172.16.0.0/12

    192.0.0.0/24
    192.0.2.0/24
    192.88.99.0/24
    192.168.0.0/16
    192.18.0.0/15
    192.51.100.0/24

    203.0.113.0/24

    208.128.0.0/11
    208.130.28.0/22
    208.130.29.0/24

    240.0.0.0/4

    255.255.255.255/32
  ]

  it_lexes_cidr6 %w[
    ::/0
    ::/1
    ::/2
    ::/96
    ::/128
    ::1/128

    ::ffff:0:0/96
    ::ffff:0:0:0/96

    100::/64
    200::/7

    64:ff9b::/96

    2000::/3
    2001::/32

    2001:0000::/29
    2001:2::/48
    2001:10::/28
    2001:20::/28
    2001:01f8::/29
    2001:0678::/29

    2001:db8::/32
    2001:db8::/48
    2001:db8:1::/64
    2001:db8:1:2::/64
    2001:db8:1234::/48

    2002::/16

    3ffe::/16
    5f00::/8

    fc00::/7
    fc00::/8
    fd00::/8

    fe80::/10
    fe80::/64

    fec0::/10

    ff00::/8

    ff02::1:ff00:0/104
    ff02::2:ff00:0/104
  ]

  it_lexes_mac %w[
    aa:bb:cc:dd:ee:ff
    AA:BB:CC:DD:EE:FF
    aA:bB:cC:dD:eE:fF
    00:00:00:00:00:00
    ff:ff:ff:ff:ff:ff
    aa-bb-cc-dd-ee-ff
    AA-BB-CC-DD-EE-FF
    aabb.ccdd.eeff
    AABB.CCDD.EEFF
    0000.0000.0000
  ]

  # UUIDs (Universally Unique Identifiers)
  #
  # RFC 4122 version 1-5
  #     v1 (timestamp)
  #     v2 (DCE security)
  #     v3 (MD5 hash)
  #     v4 (random)
  #     v5 (SHA-1 hash)
  #
  # - 0xxx (nibbles 0-7) — NCS backward compatibility (Apollo DCE)
  # - 10xx (nibbles 8-b) — RFC 4122 (Leach-Salz), the most common format
  # - 110x (nibbles c-d) — Microsoft COM/DCOM backward compatibility
  # - 111x (nibbles e-f) — reserved for future use
  #
  # RFC 9562 variants 0, 2, 6, 7
  #     v6 (reordered timestamp)
  #     v7 (Unix timestamp)
  #     v8 (custom)

  it_lexes_uuids [
    "550e8400-e29b-11d4-a716-446655440000",  # v1 (timestamp)
    "000003e8-2f68-21ec-8800-2eb17c2d55a5",  # v2 (DCE security)
    "6ba7b810-9dad-31d6-80f1-100000000000",  # v3 (MD5 hash)
    "550e8400-e29b-41d4-a716-446655440000",  # v4 (random)
    "886313e1-3b8a-5372-9b90-0c9aee199e5d",  # v5 (SHA-1 hash)
    "1ec9414c-232a-6b00-b3c8-9e6bdeced846",  # v6 (reordered timestamp)
    "017f22e2-79b0-7cc3-98c4-dc0c0c07398f",  # v7 (Unix timestamp)
    "320c3d4d-cc00-875b-8ec9-32d5f69181c0",  # v8 (custom)

    "00000000-0000-1000-8000-000000000000",  # minimum v1
    "ffffffff-ffff-1fff-bfff-ffffffffffff",  # maximum v1

    "00000000-0000-2000-8000-000000000000",  # minimum v2
    "ffffffff-ffff-2fff-bfff-ffffffffffff",  # maximum v2

    "00000000-0000-3000-8000-000000000000",  # minimum v3
    "ffffffff-ffff-3fff-bfff-ffffffffffff",  # maximum v3

    "00000000-0000-4000-8000-000000000000",  # minimum v4
    "ffffffff-ffff-4fff-bfff-ffffffffffff",  # maximum v4

    "00000000-0000-5000-8000-000000000000",  # minimum v5
    "ffffffff-ffff-5fff-bfff-ffffffffffff",  # maximum v5

    "00000000-0000-6000-8000-000000000000",  # minimum v6
    "ffffffff-ffff-6fff-bfff-ffffffffffff",  # maximum v6

    "00000000-0000-7000-8000-000000000000",  # minimum v7
    "ffffffff-ffff-7fff-bfff-ffffffffffff",  # maximum v7

    "00000000-0000-8000-8000-000000000000",  # minimum v8
    "ffffffff-ffff-8fff-bfff-ffffffffffff",  # maximum v8

    "FFFFFFFF-FFFF-4FFF-BFFF-FFFFFFFFFFFF",  # uppercase
    "aBcDeFaB-cDeF-4aBc-9DeF-aBcDeFaBcDeF",  # mixed case
    "00000000-0000-4000-8000-000000000000"   # all zeros except version/variant
  ]

  # quantity literals
  it_lexes "5 m",       :QUANTITY, ["5",    "m",     :INT]
  it_lexes "5m",        :QUANTITY, ["5",    "m",     :INT]
  it_lexes "100 km",    :QUANTITY, ["100",  "km",    :INT]
  it_lexes "3.14 kg",   :QUANTITY, ["3.14", "kg",    :DECIMAL]
  it_lexes "~1.5 m",    :QUANTITY, ["~1.5", "m",     :FLOAT]
  it_lexes "12 in",     :QUANTITY, ["12",   "in",    :INT]
  it_lexes "5 m/s",     :QUANTITY, ["5",    "m/s",   :INT]
  it_lexes "9 m/s^2",   :QUANTITY, ["9",    "m/s^2", :INT]
  it_lexes "2x",        :QUANTITY, ["2",    "x",     :INT]
  it_lexes "1 foo",     :QUANTITY, ["1",    "foo",   :INT]

  it_lexes "5 m²",      :QUANTITY, ["5", "m²",   :INT]
  it_lexes "9 m/s²",    :QUANTITY, ["9", "m/s²", :INT]

  it "does not lex unit when followed by parens" do
    lexer = described_class.new("5 foo(1)")
    token = lexer.next_token
    expect(token.type).to eq(:INT)
    expect(token.value).to eq("5")
  end

  it_lexes_currencies %w[
    $100 50¢
    £100 50p £100/-
    €100

    ¥100
  JP¥100
     100円
  CN¥100
     100元

    ₩100

    ₹500/-

    ₹100
    ₽100
    ₺100
    ₫100
  ]

  it_does_not_lex "invalid currencies", *%w[
    $500¢
  ]

  # Currency literals
  it_lexes "$4.99",  :CURRENCY, ["4.99",  "$", nil]
  it_lexes "$10",    :CURRENCY, ["10",    "$", nil]
  it_lexes "$10.50", :CURRENCY, ["10.50", "$", nil]
  it_lexes "€100",   :CURRENCY, ["100",   "€", nil]
  it_lexes "¥500",   :CURRENCY, ["500",   "¥", nil]
  it_lexes "₹500/-", :CURRENCY, ["500",   "₹", "/-"]
  it_lexes "50p",    :CURRENCY, ["50",    nil, "p"]

  # Suffix currency (cents)
  it "lexes 25¢ as CURRENCY" do
    lexer = described_class.new("25¢")
    token = lexer.next_token
    expect(token.type).to eq(:CURRENCY)
    expect(token.value).to eq(["25", nil, "¢"])
  end

  # Percentage literals
  it "lexes 15% as PERCENTAGE" do
    lexer = described_class.new("15%")
    token = lexer.next_token
    expect(token.type).to eq(:PERCENTAGE)
    expect(token.value).to eq(["15", :INT])
  end

  it "lexes 8.25% as PERCENTAGE" do
    lexer = described_class.new("8.25%")
    token = lexer.next_token
    expect(token.type).to eq(:PERCENTAGE)
    expect(token.value).to eq(["8.25", :DECIMAL])
  end

  it "lexes space-separated % as modulo operator" do
    lexer = described_class.new("10 % 3")
    t1 = lexer.next_token
    expect(t1.type).to eq(:INT)
    lexer.next_token # SP
    t3 = lexer.next_token  # %
    expect(t3.type).to eq(:%)
  end

  it "lexes · as multiplication operator" do
    lexer = described_class.new("a·b")
    expect(lexer.next_token.type).to eq(:ID)
    expect(lexer.next_token.type).to eq(:*)
    expect(lexer.next_token.type).to eq(:ID)
  end

  it "lexes ⋅ as multiplication operator" do
    lexer = described_class.new("a⋅b")
    expect(lexer.next_token.type).to eq(:ID)
    expect(lexer.next_token.type).to eq(:*)
    expect(lexer.next_token.type).to eq(:ID)
  end

  it "lexes × as multiplication operator" do
    lexer = described_class.new("a×b")
    expect(lexer.next_token.type).to eq(:ID)
    expect(lexer.next_token.type).to eq(:*)
    expect(lexer.next_token.type).to eq(:ID)
  end

  it "lexes ÷ as division operator" do
    lexer = described_class.new("a÷b")
    expect(lexer.next_token.type).to eq(:ID)
    expect(lexer.next_token.type).to eq(:/)
    expect(lexer.next_token.type).to eq(:ID)
  end

  it "lexes ∕ as division operator" do
    lexer = described_class.new("a∕b")
    expect(lexer.next_token.type).to eq(:ID)
    expect(lexer.next_token.type).to eq(:/)
    expect(lexer.next_token.type).to eq(:ID)
  end

  it "lexes superscript digits" do
    lexer = described_class.new("x²")
    expect(lexer.next_token.type).to eq(:ID)
    t = lexer.next_token
    expect(t.type).to eq(:SUPERSCRIPT)
    expect(t.value).to eq("²")
  end

  it "lexes multi-digit superscripts" do
    lexer = described_class.new("x¹²")
    expect(lexer.next_token.type).to eq(:ID)
    t = lexer.next_token
    expect(t.type).to eq(:SUPERSCRIPT)
    expect(t.value).to eq("¹²")
  end

  it "lexes a primed identifier as a single ID" do
    lexer = described_class.new("x'")
    t = lexer.next_token
    expect(t.type).to eq(:ID)
    expect(t.value.to_s).to eq("x'")
  end

  it "does not prime an identifier when the quote could open a string" do
    lexer = described_class.new("x'y'")
    t = lexer.next_token
    expect(t.type).to eq(:ID)
    expect(t.value.to_s).to eq("x")
  end

  it "lexes Δ-prefixed identifiers" do
    lexer = described_class.new("Δx")
    t = lexer.next_token
    expect(t.type).to eq(:ID)
    expect(t.value.to_s).to eq("Δx")
  end

  it "lexes √ as a prefix operator token" do
    lexer = described_class.new("√(16)")
    expect(lexer.next_token.type).to eq(:"√")
  end

  it "lexes <> as the swap operator" do
    lexer = described_class.new("a <> b")
    types = []
    10.times do
      t = lexer.next_token
      types << t.type
      break if t.type == :EOF
    end
    expect(types).to include(:"<>")
  end

  it "lexes Unicode identifiers" do
    %w[π τ ϕ φ ℯ ℇ ∞ ℎ ℏ].each do |sym|
      lexer = described_class.new(sym)
      t = lexer.next_token
      expect(t.type).to eq(:ID)
      expect(t.value).to eq(sym)
    end
  end

  # Byte array literals
  it_lexes "« »",             :BYTE_ARRAY, []
  it_lexes "« ff »",          :BYTE_ARRAY, [255]
  it_lexes "« ff 00 a5 »",    :BYTE_ARRAY, [255, 0, 165]
  it_lexes "« 54 75 6e 67 73 74 65 6e »", :BYTE_ARRAY, %w[84 117 110 103 115 116 101 110].map(&:to_i)

  it_lexes "« 0b11001100 »",  :BYTE_ARRAY, [204]
  it_lexes "« 0xff »",        :BYTE_ARRAY, [255]
  it_lexes "« 0o377 »",       :BYTE_ARRAY, [255]
  it_lexes "« 0d255 »",       :BYTE_ARRAY, [255]

  it_lexes "« ff,00,a5 »",    :BYTE_ARRAY, [255, 0, 165]
  it_lexes "« 0 f »",         :BYTE_ARRAY, [0, 15]

  it_lexes "u0xFFF9073656C6966B", :WVALUE, "u0xFFF9073656C6966B"

  it "lexes byte array with interpolation" do
    lexer = described_class.new("« ff [x] 00 »")
    token = lexer.next_token
    expect(token.type).to eq(:BYTE_ARRAY_INTERP)
    expect(token.value).to eq([[:bytes, [255]], [:expr, "x"], [:bytes, [0]]])
  end

  it "raises on unterminated byte array" do
    lexer = described_class.new("« ff 00")
    expect { lexer.next_token }.to raise_error(Tungsten::Error, /unterminated byte array/)
  end

  it "raises on byte value out of range" do
    lexer = described_class.new("« 0d256 »")
    expect { lexer.next_token }.to raise_error(Tungsten::Error, /out of range/)
  end

  it "raises on unexpected character in byte array" do
    lexer = described_class.new("« zz »")
    expect { lexer.next_token }.to raise_error(Tungsten::Error, /unexpected character/)
  end

  # Key literals
  it_lexes '#[CTRL+D]',           :KEY, "CTRL+D"
  it_lexes '#[ctrl+d]',           :KEY, "ctrl+d"
  it_lexes '#[C-d]',              :KEY, "C-d"
  it_lexes '#[SHIFT+ENTER]',      :KEY, "SHIFT+ENTER"
  it_lexes '#[S-t u n g]',        :KEY, "S-t u n g"
  it_lexes '#[F1]',               :KEY, "F1"
  it_lexes '#[A]',                :KEY, "A"
  it_lexes '#[CTRL]',             :KEY, "CTRL"
  it_lexes '#[CTRL+ALT+SHIFT+A]', :KEY, "CTRL+ALT+SHIFT+A"

  it "raises on empty key literal" do
    lexer = described_class.new('#[]')
    expect { lexer.next_token }.to raise_error(Tungsten::Error, /empty key literal/)
  end

  it "raises on unterminated key literal" do
    lexer = described_class.new('#[CTRL+D')
    expect { lexer.next_token }.to raise_error(Tungsten::Error, /unterminated key literal/)
  end
end

RSpec.describe Tungsten::Lexer, order: :defined do
  include_examples "a Tungsten lexer"
end

RSpec.describe Tungsten::CodepointLexer, order: :defined do
  include_examples "a Tungsten lexer"

  it "matches the reference lexer token stream on compiler sources" do
    root = File.expand_path("../../..", __dir__)
    paths = [File.join(root, "compiler/tungsten.w")] + Dir[File.join(root, "compiler/lib/*.w")]

    paths.each do |path|
      reference = Tungsten::Lexer.new(File.read(path))
      codepoint = described_class.new(File.read(path))
      reference.file = path
      codepoint.file = path

      loop do
        expected = reference.next_token.clone
        actual = codepoint.next_token.clone

        expect([actual.type, actual.value]).to eq([expected.type, expected.value]), path
        break if expected.type == :EOF
      end
    end
  end
end
