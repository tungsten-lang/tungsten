# 2. Lexical Analysis 

A Tungsten program is read by a lexical analyzer, or _lexer_, which converts an input stream of Unicode characters into a stream of _tokens_. If more than one token can match a sequence of characters in the source file, the lexer will form the longest possible lexical element. The stream of tokens output from the lexer is processed by a _parser_. Some tokens are discarded after processing.

This chapter describes how the lexical analyzer breaks a file into tokens.

Besides `NL`, `SP`, `INDENT`, and `DEDENT`; the following categories of tokens exist: _identifiers_, _keywords_, _literals_, _operators_, _delimiters_, and _comments_.

When defining _lexical_ syntax, all whitespace is described explicitly.

## 2.1 Source code

Tungsten code **must** be encoded as UTF-8.

Tungsten code may exist in source files, or passed as a string to the `eval` function. In either case, the code is a sequence of Unicode characters processed by a lexer. Lexical analysis of the character stream, according to the grammar defined in this chapter, results in a stream of tokens. These tokens form the input of the parser grammar defined in later chapters of this specification.

If a file cannot be decoded as UTF-8, an `Encoding<Error>` **must** be raised.

<small>Note: a UTF-8 byte order mark (BOM) `U+FEFF ZERO WIDTH NO-BREAK SPACE` **may** be the first character present, but is neither required nor recommended.</small>

Text in source files **must not** be canonicalized or normalized by the lexer. For simplicity, this document will use the unqualified term _character_ to refer to a single Unicode code point.

Tungsten source files **may** have the following extensions: `.w`, `.wc`, `.ws`, `.wd`.

## 2.2 Line structure

A Tungsten program is divided into one or more _logical lines_.

### 2.2.1 Logical lines

The end of a logical line is represented by the token `NL`. Statements cannot cross logical line boundaries except where `NL` is allowed by the syntax (_e.g._, between statements in compound statements). A logical line is constructed from one or more _physical lines_ by following the explicit or implicit _line joining_ rules.

### 2.2.2 Physical lines

A physical line is a sequence of characters terminated by a line terminator. In Tungsten, the only valid line terminators are the `U+000A LINE FEED` character and the end of file (or end of input).

    NL = (U+0A | EOF) .

These **must not** be recognized as line terminators:

* `VT`:  `U+000B LINE TABULATION`
* `FF`:  `U+000C FORM FEED`
* `CR`:  `U+000D CARRIAGE RETURN`
* `LS`:  `U+2028 LINE SEPARATOR`
* `PS`:  `U+2029 PARAGRAPH SEPARATOR`
* `NEL`: `U+0085 NEXT LINE`
* `CR LF`: `CR` followed by `LF`
* `LF CR`: `LF` followed by `CR`

Tungsten does not impose any limits on the length of a line.

### 2.2.3 Explicit line joining

When a physical line begins with zero or more spaces followed by a period `^\s*\.` it will be joined with the preceding logical line, removing the whitespace and any comments in between.

    # This code
    list.select &.nonzero?
        .uniq               # only one of each
        .sort

    # will be interpreted as
    list.select(&:nonzero?).uniq.sort

<small>_Note: Joining lines with a backslash is not supported as it frequently results in hard to read code._</small>

### 2.2.4 Implicit line joining

Expressions contained within the following pairs can be split over more than one physical line:

     ( … )  parentheses
     [ … ]  square brackets
     { … }  curly braces
    <[ … ]> angle square pairs
    <( … )> angle parentheses
    << … >> double angle brackets

     %i[  ] array of symbols
     %w[  ] array of words
    %wc[  ] array of words for case
    
    months = [ 'January', 'February', 'March'     # List of month names
             , 'April',   'May',      'June'
             , 'July',    'August',   'September'
             , 'October', 'November', 'December'
             ]

Implicitly continued lines can be commented. The indentation of the continuation lines is not important. Blank continuation lines are allowed. There is no `NL` token between implicitly continued lines.

### 2.2.5 Blank Lines

A physical line that contains only whitespace with an optional comment is ignored, _i.e._, no `NL` token is generated.

### 2.2.6 End of File

Tungsten source is terminated by whichever comes first:

* Physical end of file
* U+0000
* U+001A

An `EOF` token is used to indicate the end of file.

## 2.3 Whitespace

Tungsten's grammar is more particular about whitespace than most other languages.

    SP = "\U{20}" .

One or more spaces (`U+0020 SPACE`) are collapsed into a single `SP` token. In many places, the grammar is disambiguated by adding whitespace.

Example: `10m/s^2` is a decimal literal defining an amount of acceleration, `10m/s ^ 2` means the _2nd power of 10m/s_.

Infix operators must be surrounded by whitespace characters.

Tab characters (`U+0009 CHARACTER TABULATION`) are only allowed within string literals.

## 2.4 Indentation

Indentation in source files must be two spaces. Lines in the same scope must have the same indent. Changes in indentation produce `INDENT` and `DEDENT` tokens.

## 2.5 Comments

A comment starts with an unquoted hash character `#` followed by a space or bang, and terminates at the end of the physical line. A comment signifies the end of the logical line unless the implicit line joining rules apply. Comments are ignored by the syntax; they do not emit tokens.

    Comment = "#" (SP | "!") { ~ NL } NL .

## 2.6 Preprocessing Directives

Preprocessing directives are governed by tokens described by the following lexical definition:

    Letter  = "A"…"Z" | "_" .
    Token   = "#" Letter { Letter } .
    Boolean = 'true' | 'false' .
    Rule    = Token "=" Boolean .

<small>_Note: Preprocessing tokens beginning with `W_` are reserved for use by the implementation._</small>

    puts "starting [Time.now]" #W_DEBUG
    puts "loaded [file]"       #W_VERBOSE

    # TODO: Refine this syntax
    #[development]
    #![profile]

## 2.7 Identifiers and Keywords

Identifiers (also referred to as _names_) are described by the following lexical definitions.

The syntax of identifiers in Tungsten is based on _[UAX #31: Unicode Identifier and Pattern Syntax][tr31]_, with elaboration and changes as defined below:

Within the ASCII range `U+0001`…`U+007F`, the valid characters for identifiers are the uppercase letters `A`…`Z`, the lowercase letters `a`…`z`, the underscore `_` and, except as an _identifier start_, the digits `0`…`9`.

Identifiers are unlimited in length. Case is significant.

    Identifier   = XID_Start { XID_Continue } .
    ID_Start     = (* all characters in general categories Lu, Ll, Lt, Lm, Lo, Nl, the underscore, and characters with the Other_ID_Start property *) .
    ID_Continue  = (* all characters in ID_Start, plus characters in the categories Mn, Mc, Nd, Pc, and others with the Other_ID_Continue property *) .
    XID_Start    = (* all characters in ID_Start whose NFKC normalization is in "ID_Start { XID_Continue }" *) .
    XID_Continue = (* all characters in ID_Continue whose NFKC normalization is in "ID_Continue" *) .

Token: `ID`

The Unicode category codes mentioned above stand for:

    * Lu uppercase letters
    * Ll lowercase letters
    * Lt titlecase letters
    * Lm modifier letters
    * Lo other letters
    * Nl letter numbers
    * Mn nonspacing marks
    * Mc spacing combining marks
    * Nd decimal numbers
    * Pc connector punctuations
    * Other_ID_Start    explicit list of characters in PropList.txt to support backwards compatibility
    * Other_ID_Continue likewise

All identifiers are converted into the normal form NFKC while parsing; comparison of identifiers is based on NFKC.

Characters in the category Currency_Symbol (Sc) are reserved for use by decimal literals.

### 2.7.1 Keywords

The following identifiers are used as reserved words, or _keywords_ of the language, and cannot be used as identifiers.

They must be spelled exactly as written here:

    break
    case continue
    else elsif exit
    false
    if in
    next nil
    raise redo rescue retry return
    self super
    trait true
    unless until use
    when while
    yield

    __DIR__
    __FILE__
    __LINE__
    __METHOD__
    __MODULE__

The following tokens are reserved for future expansion of the Tungsten language:

    asm async await
    macro
    of out
    ptr
    secret sync
    type
    uniq
    with

    mut mod freeze
    safe unsafe

    always and as assert assigns at
    bad begin by
    class compare
    do
    end ensure error every export extends extern
    fn for from
    is
    ln
    module
    noop not
    or
    private protected public
    reraise rm
    then


    abort abstract alias align always args asm assert assigns async atomic auto await
    base begin binding bitstype body bool byte bytetype
    cache cast catch char clone compile const continue
    debug default defer deferred defined? del delegate delete delta deprecated done dynamic
    eager ensure enum eps eval event every except exec exit export external
    factory fail fallthrough field final finally for foreach foreign from function
    get global goto guard
    immutable implements implicit import imports include inherit inline interface internal invariant involatile item
    lambda lazy let library load local loop
    macro map match me mixin mutable
    namespace new none nothrow null
    object of on operator out override
    package packed parallel parse part perform pragma privately proc property pub pure
    raises range record ref repeat require restrict resume rethrow
    safe scope sealed set shadow shared sizeof static struct suspend switch sync synchronized
    template test this throw throws to trait transient trap try type typealias typedef typeof
    undef undefined union unreachable unsafe use using
    val var version void volatile
    with without

    INFINITY ∞
    NAN
    quietly

    on off
    yes no
    good bad

    # maybe
    done
    elif extern

    # magic methods
    @@caller
    @@message

    # Unused Ruby keywords
    BEGIN
    END
    __ENCODING__
    __END__

Backquote-enclosed strings can be used if you _really_ need to use a reserved word as an identifier.

    crop.`yield` * 1⋅bushel⋅acre⁻¹

### 2.7.2 Context-Dependent Constants

| Constant   | Description                                |
| ---------- | ------------------------------------------ |
| `__DIR__`  | The directory name of the current script   |
| `__FILE__` | The file name of the current script        |
| `__LINE__` | The number of the current line in the file |

### 2.7.3 Reserved classes of identifiers

@todo Python reserves `_*`, `__*__`, and `__*` http://docs.python.org/3.4/reference/lexical_analysis.html

## 2.8 String literals

Literals are notations for constant values of some built-in types.

### 2.8.1 Characters

A Character represents one Unicode code point.

Character literals are described by the following lexical definition:

    Hex              = "0"…"9" | "A"…"F" .
    LiteralCharacter = "U+" [Hex] [Hex] Hex Hex Hex Hex .

Examples:

    # Range of allowed code points
    U+0000…U+10FFFF

    # LATIN CAPITAL LETTER A
    U+0041
    U+000041

    U+0041.class
    => CodePoint

    U+0041 == "\u{41}".codepoints.first == "A".codepoints.first

A character may also be written with a `:-` prefix followed by a single character, or a backslash escape. The value of the literal is the code point of that character:

    :-)     # => the character ")"  (code point 41)
    :-(     # => the character "("  (code point 40)
    :-A     # => the character "A"  (code point 65)
    :-\n    # => LINE FEED          (code point 10)

The `:-` must be followed by a non-whitespace character; `:- ` (with a space) is not a character literal. This is a general character-literal form, not a fixed table of emoticons — `:-X` always denotes the character `X`. The recognized backslash escapes are `\0`, `\n`, `\r`, `\t`, `\s`, `\\`, `\'`, and `\"`.

### 2.8.2 Strings

A String represents a sequence of Unicode code points.

String literals are described by the following lexical definitions:

    LiteralString = '"' { StringItem } '"' .
    StringItem    = StringChar | StringEscape | StringExp .
    StringChar    = (* any Unicode character except "\" or newline or '"' *) .
    Character     = "\U{00}"…"\U{10FFFF}" .
    StringExp     = "[" Expression "]" .
    StringEscape  =
                  | "\0"
                  | "\a"
                  | "\b"
                  | "\c"
                  | "\e"
                  | "\f"
                  | "\l"
                  | "\n"
                  | "\r"
                  | "\s"
                  | "\t"
                  | "\v"
                  | "\""
                  | "\'"
                  | "\["
                  | "\\"
                  | "\x" Hex Hex
                  | "\o" Octal Octal Octal
                  | "\u" Hex Hex Hex Hex
                  | "\U[" { Hex Hex [Hex Hex] [Hex Hex] } "]"
                  | "\N[" Characters { "," Characters } "]"
                  | "\P[" Characters [ "=" Characters ] "]"
                  | "\" Character
                  .

String literals are delimited by matching double quotes. The backslash character is used to escape characters that are unprintable or otherwise have special meaning, such as a newline, backslash itself, or the double quote character.

The following escape sequences are recognized:

| Escape sequence      | Control | Unicode    | Abbr | Character name              | Description, _C0 of ISO 646_                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| -------------------- | ------- | ---------- | ---- | --------------------------- | ------------------------------------------                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| `\0`                 | `\@`    | [U+0000][] | NUL  | NULL                        | A control character used to accomplish media-fill or time-fill. Null characters may be inserted into or removed from a stream of data without affecting the information content of that stream. But then the addition or removal of these characters may affect the information layout and/or the control of equipment.                                                                                                                                                                |
|                      | `\^A`   | [U+0001][] | SOH  | START OF HEADING            | A transmission control character used as the first character of a heading of an information message.                                                                                                                                                                                                                                                                                                                                                                                   |
|                      | `\^B`   | [U+0002][] | STX  | START OF TEXT               | A transmission control character which precedes a text and which is used to terminate a heading.                                                                                                                                                                                                                                                                                                                                                                                       |
|                      | `\^C`   | [U+0003][] | ETX  | END OF TEXT                 | A transmission control character which terminates a text.                                                                                                                                                                                                                                                                                                                                                                                                                              |
|                      | `\^D`   | [U+0004][] | EOT  | END OF TRANSMISSION         | A transmission control character used to indicate the conclusion of the transmission of one or more texts.                                                                                                                                                                                                                                                                                                                                                                             |
|                      | `\^E`   | [U+0005][] | ENQ  | ENQUIRY                     | A transmission control character used as a request for a response from a remote station; the response may include station identification and/or station status. When a "Who are you" function is required on the general switched transmission network, the first use of ENQ after the connection is established shall have the meaning "Who are you" (station identification). Subsequent use of ENQ may, or may not, include the function "Who are you", as determined by agreement. |
|                      | `\^F`   | [U+0006][] | ACK  | ACKNOWLEDGE                 | A transmission control character transmitted by a receiver as an affirmative response to the sender.                                                                                                                                                                                                                                                                                                                                                                                   |
| `\a`                 | `\^G`   | [U+0007][] | BEL  | ALERT                       | A control character that is used when there is a need to call for attention; it may control alarm or attention devices.                                                                                                                                                                                                                                                                                                                                                                |
| `\b`                 | `\^H`   | [U+0008][] | BS   | BACKSPACE                   | A format effector which moves the active position one character position backwards on the same line.                                                                                                                                                                                                                                                                                                                                                                                   |
| `\t`                 | `\^I`   | [U+0009][] | TAB  | CHARACTER TABULATION        | A format effector which advances the active position to the next pre-determined character position on the same line.                                                                                                                                                                                                                                                                                                                                                                   |
| `\n`, `\l`           | `\^J`   | [U+000A][] | LF   | LINE FEED                   | A format effector which advances the active position to the same character position of the next line.                                                                                                                                                                                                                                                                                                                                                                                  |
| `\v`                 | `\^K`   | [U+000B][] | VT   | LINE TABULATION             | A format effector which advances the active position to the same character position on the next pre-determined line.                                                                                                                                                                                                                                                                                                                                                                   |
| `\f`                 | `\^L`   | [U+000C][] | FF   | FORM FEED                   | A format effector which advances the active position to the same character position on a pre-determined line of the next form or page.                                                                                                                                                                                                                                                                                                                                                 |
| `\r`, `\c`           | `\^M`   | [U+000D][] | CR   | CARRIAGE RETURN             | A format effector which moves the active position to the first character position on the same line.                                                                                                                                                                                                                                                                                                                                                                                    |
|                      | `\^N`   | [U+000E][] | SO   | SHIFT OUT                   | A control character which is used in conjunction with SHIFT IN and ESCAPE to extend the graphic character set of the code. It may alter the meaning of octets 33 - 126 (dec). The effect of this character when using code extension techniques is described in International Standard ISO 2022.                                                                                                                                                                                       |
|                      | `\^O`   | [U+000F][] | SI   | SHIFT IN                    | A control character which is ued in conjunction with SHIFT OUT and ESCAPE to extend the graphic character set of the code. It may reinstate the standard meanings of the octets which follow it. The effect of this character when using code extension techniques is described in International Standard ISO 2022.                                                                                                                                                                    |
|                      | `\^P`   | [U+0010][] | DLE  | DATA LINK ESCAPE            | A transmission control character which will change the meaning of a limited number of contiguously following characters. It is used exclusively to provide supplementary data transmission control functions. Only graphic characters and trensmission control characters can be used in DLE sequences.                                                                                                                                                                                |
|                      | `\^Q`   | [U+0011][] | DC1  | DEVICE CONTROL ONE          | A device control character which is primarily intended for turning on or starting an ancillary device. If it is not required for this purpose, it may be used to restore a device to the basic mode of operation (see also DC2 and DC3), or for any other device control function not provided by other DCs.                                                                                                                                                                           |
|                      | `\^R`   | [U+0012][] | DC2  | DEVICE CONTROL TWO          | A device control character which is primarily intended for turning on or starting an ancillary device. If it is not required for this purpose, it may be used to set a device to a special mode of operation (in which case DC1 is used to restore normal operation), or for any other device control function not provided by other DCs.                                                                                                                                              |
|                      | `\^S`   | [U+0013][] | DC3  | DEVICE CONTROL THREE        | A device control character which is primarily intended for turning off or stopping an ancillary device. This function may be a secondary level stop, for example, wait, pause, stand-by or halt (in which case DC1 is used to restore normal operation). If it is not required for this purpose, it may be used for any other device control function not provided by other DCs.                                                                                                       |
|                      | `\^T`   | [U+0014][] | DC4  | DEVICE CONTROL FOUR         | A device control character which is primarily intended for turning off, stopping or interrupting an ancillary device. If it is not required for this purpose, it may be used for any other device control function not provided by other DCs.                                                                                                                                                                                                                                          |
|                      | `\^U`   | [U+0015][] | NAK  | NEGATIVE ACKNOWLEDGE        | A transmission control character transmitted by a receiver as a negative response to the sender.                                                                                                                                                                                                                                                                                                                                                                                       |
|                      | `\^V`   | [U+0016][] | SYN  | SYNCHRONOUS IDLE            | A transmission control character used by a synchronous transmission system in the absence of any other character (idle condition) to provide a signal from which synchronism may be achieved or retained between data terminal equipment.                                                                                                                                                                                                                                              |
|                      | `\^W`   | [U+0017][] | ETB  | END OF TRANSMISSION BLOCK   | A transmission control character used to indicate the end of a transmission block of data where data is divided into such blocks for transmission purposes.                                                                                                                                                                                                                                                                                                                            |
|                      | `\^X`   | [U+0018][] | CAN  | CANCEL                      | A character, or the first character of a sequence, indicating that the data preceding it is in error. As a result, this data is to be ignored. The specific meaning of this character must be defined for each application and/or between sender and recipient.                                                                                                                                                                                                                        |
|                      | `\^Y`   | [U+0019][] | EM   | END OF MEDIUM               | A control character that may be used to identify the physical end of a medium, or the end of the used portion of a medium, or the end of the wanted portion of data recorded on a medium. The position of this character does not necessarily correspond to the physical end of the medium.                                                                                                                                                                                            |
|                      | `\^Z`   | [U+001A][] | SUB  | SUBSTITUTE                  | A control character used in the place of a character that has been found to be invalid or in error. SUB is intended to be introduced by automatic means.                                                                                                                                                                                                                                                                                                                               |
| `\e`                 | `\^[`   | [U+001B][] | ESC  | ESCAPE                      | A control character which is used to provide additional control functions. It alters the meaning of a limited number of contiguously following bit combinations. The use of this character is specified in Internation Standard ISO 2022.                                                                                                                                                                                                                                              |
|                      | `\^\`   | [U+001C][] | FS   | INFORMATION SEPARATOR FOUR  | A control character used to separate and qualify data logically; its specific meaning has to be specified for each application. If this character is used in hierarchical order, it delimits a data item called a _file_.                                                                                                                                                                                                                                                              |
|                      | `\^]`   | [U+001D][] | GS   | INFORMATION SEPARATOR THREE | A control character used to separate and qualify data logically; its specific meaning has to be specified for each application. If this character is used in hierarchical order, it delimits a data item called a _group_.                                                                                                                                                                                                                                                             |
|                      | `\^^`   | [U+001E][] | RS   | INFORMATION SEPARATOR TWO   | A control character used to separate and qualify data logically; its specific meaning has to be specified for each application. If this character is used in hierarchical order, it delimits a data item called a _record_.                                                                                                                                                                                                                                                            |
|                      | `\^_`   | [U+001F][] | US   | INFORMATION SEPARATOR ONE   | A control character used to separate and qualify data logically; its specific meaning has to be specified for each application. If this character is used in hierarchical order, it delimits a data item called a _unit_.                                                                                                                                                                                                                                                              |
| `\s`                 |         | [U+0020][] | SP   | SPACE                       |                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `\"`                 |         | [U+0022][] |      | QUOTATION MARK              |                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `\'`                 |         | [U+0027][] |      | APOSTROPHE                  |                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `\[`                 |         | [U+005B][] |      | LEFT SQUARE BRACKET         |                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `\\`                 |         | [U+005C][] |      | REVERSE SOLIDUS             |                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| ``\` ``              |         | [U+0060][] |      | GRAVE ACCENT                |                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `\d`                 | `\?`    | [U+007F][] | DEL  | DELETE                      |                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `[expression]`       |         |            |      |                             | Interpolate value of _expression_                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| `\oddd`              |         |            |      |                             | Unicode codepoint with octal value 'ddd'                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| `\xhh`               |         |            |      |                             | Unicode codepoint with hex value 'hh'                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| `\uhhhh`             |         |            |      |                             | Unicode codepoint with hex value 'hhhh'                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| `\U[xx xxxx xxxxxx]` |         |            |      |                             | 1 or more Unicode codepoints, by hex value                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| `\N[NAME 1, NAME 2]` |         |            |      |                             | 1 or more Unicode codepoints, by name                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| `\P[prop=value]`     |         |            |      |                             | 1 or more Unicode codepoints, by property                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| `\x`                 |         |            |      |                             | _x_                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |

* See [C0 and C1 control codes](https://en.wikipedia.org/wiki/C0_and_C1_control_codes)


[U+0000]: http://codepoints.net/U+0000
[U+0001]: http://codepoints.net/U+0001
[U+0002]: http://codepoints.net/U+0002
[U+0003]: http://codepoints.net/U+0003
[U+0004]: http://codepoints.net/U+0004
[U+0005]: http://codepoints.net/U+0005
[U+0006]: http://codepoints.net/U+0006
[U+0007]: http://codepoints.net/U+0007
[U+0008]: http://codepoints.net/U+0008
[U+0009]: http://codepoints.net/U+0009
[U+000A]: http://codepoints.net/U+000A
[U+000B]: http://codepoints.net/U+000B
[U+000C]: http://codepoints.net/U+000C
[U+000D]: http://codepoints.net/U+000D
[U+000E]: http://codepoints.net/U+000E
[U+000F]: http://codepoints.net/U+000F
[U+0010]: http://codepoints.net/U+0010
[U+0011]: http://codepoints.net/U+0011
[U+0012]: http://codepoints.net/U+0012
[U+0013]: http://codepoints.net/U+0013
[U+0014]: http://codepoints.net/U+0014
[U+0015]: http://codepoints.net/U+0015
[U+0016]: http://codepoints.net/U+0016
[U+0017]: http://codepoints.net/U+0017
[U+0018]: http://codepoints.net/U+0018
[U+0019]: http://codepoints.net/U+0019
[U+001A]: http://codepoints.net/U+001A
[U+001B]: http://codepoints.net/U+001B
[U+001C]: http://codepoints.net/U+001C
[U+001D]: http://codepoints.net/U+001D
[U+001E]: http://codepoints.net/U+001E
[U+001F]: http://codepoints.net/U+001F
[U+0020]: http://codepoints.net/U+0020
[U+0022]: http://codepoints.net/U+0022
[U+0027]: http://codepoints.net/U+0027
[U+005B]: http://codepoints.net/U+005B
[U+005C]: http://codepoints.net/U+005C
[U+0060]: http://codepoints.net/U+0060
[U+007F]: http://codepoints.net/U+007F

### 2.8.3 ASCII-only Strings

An ASCII string represents a sequence of ASCII characters.

ASCII string literals are described by the following lexical definitions:

    LiteralASCII = "'" { ASCIIPart } "'" .
    ASCIIPart    = ASCIIChar | ASCIIEscape | ASCIIExp .
    ASCIIChar    = (* any ASCII character except "\" or newline or "'" *) .
    Character    = "\U{00}"…"\U{10FFFF}" .
    ASCIIExp     = "[" Expression "]" .
    ASCIIEscape  =
                 | "\0"
                 | "\a"
                 | "\b"
                 | "\c"
                 | "\e"
                 | "\f"
                 | "\l"
                 | "\n"
                 | "\r"
                 | "\s"
                 | "\t"
                 | "\v"
                 | "\""
                 | "\'"
                 | "\["
                 | "\\"
                 | "\x" Hex Hex
                 | "\o" Octal Octal Octal
                 | "\" Character
                 .

```
|b5 b6 b7 ---------> |000|001|010|011|100|101|110|111|
|b4 |b3 |b2 |b1 |r\c | - | - | - | - | - | - | - | - |
| 0 | 0 | 0 | 0 |  0 |NUL|DLE|SP | 0 | @ | P | ` | p |
| 0 | 0 | 0 | 1 |  1 |SOH|DC1| ! | 1 | A | Q | a | q |
| 0 | 0 | 1 | 0 |  2 |STX|DC2| " | 2 | B | R | b | r |
| 0 | 0 | 1 | 1 |  3 |ETX|DC3| # | 3 | C | S | c | s |
| 0 | 1 | 0 | 0 |  4 |EOT|DC4| $ | 4 | D | T | d | t |
| 0 | 1 | 0 | 1 |  5 |ENQ|NAK| % | 5 | E | U | e | u |
| 0 | 1 | 1 | 0 |  6 |ACK|SYN| & | 6 | F | V | f | v |
| 0 | 1 | 1 | 1 |  7 |BEL|ETB| ' | 7 | G | W | g | w |
| 1 | 0 | 0 | 0 |  8 | BS|CAN| ( | 8 | H | X | h | x |
| 1 | 0 | 0 | 1 |  9 | HT| EM| ) | 9 | I | Y | i | y |
| 1 | 0 | 1 | 0 | 10 | LF|SUB| * | : | J | Z | j | z |
| 1 | 0 | 1 | 1 | 11 | VT|ESC| + | ; | K | [ | k | { |
| 1 | 1 | 0 | 0 | 12 | FF| FS| , | < | L | \ | l | | |
| 1 | 1 | 0 | 1 | 13 | CR| GS| - | = | M | ] | m | } | 
| 1 | 1 | 1 | 0 | 14 | SO| RS| . | > | N | ^ | n | ~ |
| 1 | 1 | 1 | 1 | 15 | SI| US| / | ? | O | _ | o |DEL|
```

| Binary     | Oct   | Dec | Hex  | Abr |     | C  | Name                          |
| ---------- | ----- | --- | ---- | --- | --  | -- | ----------------------------- |
| 0b000_0000 | 0o000 | 0   | 0x00 | NUL | ^@  | \0 | Null                          |
| 0b000_0001 | 0o001 | 1   | 0x01 | SOH | ^A  |    | Start of Heading              |
| 0b000_0010 | 0o002 | 2   | 0x02 | STX | ^B  |    | Start of Text                 |
| 0b000_0011 | 0o003 | 3   | 0x03 | ETX | ^C  |    | End of Text                   |
| 0b000_0100 | 0o004 | 4   | 0x04 | EOT | ^D  |    | End of Transmission           |
| 0b000_0101 | 0o005 | 5   | 0x05 | ENQ | ^E  |    | Enquiry                       |
| 0b000_0110 | 0o006 | 6   | 0x06 | ACK | ^F  |    | Acknowledgement               |
| 0b000_0111 | 0o007 | 7   | 0x07 | BEL | ^G  | \a | Bell                          |
| 0b000_1000 | 0o010 | 8   | 0x08 | BS  | ^H  | \b | Backspace                     |
| 0b000_1001 | 0o011 | 9   | 0x09 | HT  | ^I  | \t | Horizontal Tab                |
| 0b000_1010 | 0o012 | 10  | 0x0A | LF  | ^J  | \n | Line Feed                     |
| 0b000_1011 | 0o013 | 11  | 0x0B | VT  | ^K  | \v | Vertical Tab                  |
| 0b000_1100 | 0o014 | 12  | 0x0C | FF  | ^L  | \f | Form Feed                     |
| 0b000_1101 | 0o015 | 13  | 0x0D | CR  | ^M  | \r | Carraige Return               |
| 0b000_1110 | 0o016 | 14  | 0x0E | SO  | ^N  |    | Shift Out                     |
| 0b000_1111 | 0o017 | 15  | 0x0F | SI  | ^O  |    | Shift In                      |
| 0b001_0000 | 0o020 | 16  | 0x10 | DLE | ^P  |    | Data Link Escape              |
| 0b001_0001 | 0o021 | 17  | 0x11 | DC1 | ^Q  |    | Device Control 1 (often XON)  |
| 0b001_0010 | 0o022 | 18  | 0x12 | DC2 | ^R  |    | Device Control 2              |
| 0b001_0011 | 0o023 | 19  | 0x13 | DC3 | ^S  |    | Device Control 3 (often XOFF) |
| 0b001_0100 | 0o024 | 20  | 0x14 | DC4 | ^T  |    | Device Control 4              |
| 0b001_0101 | 0o025 | 21  | 0x15 | NAK | ^U  |    | Negative Acknowledgement      |
| 0b001_0110 | 0o026 | 22  | 0x16 | SYN | ^V  |    | Synchronous Idle              |
| 0b001_0111 | 0o027 | 23  | 0x17 | ETB | ^W  |    | End of Transmission Block     |
| 0b001_1000 | 0o030 | 24  | 0x18 | CAN | ^X  |    | Cancel                        |
| 0b001_1001 | 0o031 | 25  | 0x19 | EM  | ^Y  |    | End of Medium                 |
| 0b001_1010 | 0o032 | 26  | 0x1A | SUB | ^Z  |    | Substitute                    |
| 0b001_1011 | 0o033 | 27  | 0x1B | ESC | ^\[ | \e | Escape                        |
| 0b001_1100 | 0o034 | 28  | 0x1C | FS  | ^\  |    | File Separator                |
| 0b001_1101 | 0o035 | 29  | 0x1D | GS  | ^]  |    | Group Separator               |
| 0b001_1110 | 0o036 | 30  | 0x1E | RS  | ^^  |    | Record Separator              |
| 0b001_1111 | 0o037 | 31  | 0x1F | US  | ^_  |    | Unit Separator                |
| 0b010_0000 | 0o040 | 32  | 0x20 |     |     |    |                               |
| 0b010_0001 | 0o041 | 33  | 0x21 | !   |     |    |                               |
| 0b010_0010 | 0o042 | 34  | 0x22 | "   |     |    |                               |
| 0b010_0011 | 0o043 | 35  | 0x23 | #   |     |    |                               |
| 0b010_0100 | 0o044 | 36  | 0x24 | $   |     |    |                               |
| 0b010_0101 | 0o045 | 37  | 0x25 | %   |     |    |                               |
| 0b010_0110 | 0o046 | 38  | 0x26 | &   |     |    |                               |
| 0b010_0111 | 0o047 | 39  | 0x27 | '   |     |    |                               |
| 0b010_1000 | 0o050 | 40  | 0x28 | (   |     |    |                               |
| 0b010_1001 | 0o051 | 41  | 0x29 | )   |     |    |                               |
| 0b010_1010 | 0o052 | 42  | 0x2A | *   |     |    |                               |
| 0b010_1011 | 0o053 | 43  | 0x2B | +   |     |    |                               |
| 0b010_1100 | 0o054 | 44  | 0x2C | ,   |     |    |                               |
| 0b010_1101 | 0o055 | 45  | 0x2D | -   |     |    |                               |
| 0b010_1110 | 0o056 | 46  | 0x2E | .   |     |    |                               |
| 0b010_1111 | 0o057 | 47  | 0x2F | /   |     |    |                               |
| 0b011_0000 | 0o060 | 48  | 0x30 | 0   |     |    |                               |
| 0b011_0001 | 0o061 | 49  | 0x31 | 1   |     |    |                               |
| 0b011_0010 | 0o062 | 50  | 0x32 | 2   |     |    |                               |
| 0b011_0011 | 0o063 | 51  | 0x33 | 3   |     |    |                               |
| 0b011_0100 | 0o064 | 52  | 0x34 | 4   |     |    |                               |
| 0b011_0101 | 0o065 | 53  | 0x35 | 5   |     |    |                               |
| 0b011_0110 | 0o066 | 54  | 0x36 | 6   |     |    |                               |
| 0b011_0111 | 0o067 | 55  | 0x37 | 7   |     |    |                               |
| 0b011_1000 | 0o070 | 56  | 0x38 | 8   |     |    |                               |
| 0b011_1001 | 0o071 | 57  | 0x39 | 9   |     |    |                               |
| 0b011_1010 | 0o072 | 58  | 0x3A | :   |     |    |                               |
| 0b011_1011 | 0o073 | 59  | 0x3B | ;   |     |    |                               |
| 0b011_1100 | 0o074 | 60  | 0x3C | <   |     |    |                               |
| 0b011_1101 | 0o075 | 61  | 0x3D | =   |     |    |                               |
| 0b011_1110 | 0o076 | 62  | 0x3E | >   |     |    |                               |
| 0b011_1111 | 0o077 | 63  | 0x3F | ?   |     |    |                               |
| 0b100_0000 | 0o100 | 64  | 0x40 | @   |     |    |                               |
| 0b100_0001 | 0o101 | 65  | 0x41 | A   |     |    |                               |
| 0b100_0010 | 0o102 | 66  | 0x42 | B   |     |    |                               |
| 0b100_0011 | 0o103 | 67  | 0x43 | C   |     |    |                               |
| 0b100_0100 | 0o104 | 68  | 0x44 | D   |     |    |                               |
| 0b100_0101 | 0o105 | 69  | 0x45 | E   |     |    |                               |
| 0b100_0110 | 0o106 | 70  | 0x46 | F   |     |    |                               |
| 0b100_0111 | 0o107 | 71  | 0x47 | G   |     |    |                               |
| 0b100_1000 | 0o110 | 72  | 0x48 | H   |     |    |                               |
| 0b100_1001 | 0o111 | 73  | 0x49 | I   |     |    |                               |
| 0b100_1010 | 0o112 | 74  | 0x4A | J   |     |    |                               |
| 0b100_1011 | 0o113 | 75  | 0x4B | K   |     |    |                               |
| 0b100_1100 | 0o114 | 76  | 0x4C | L   |     |    |                               |
| 0b100_1101 | 0o115 | 77  | 0x4D | M   |     |    |                               |
| 0b100_1110 | 0o116 | 78  | 0x4E | N   |     |    |                               |
| 0b100_1111 | 0o117 | 79  | 0x4F | O   |     |    |                               |
| 0b101_0000 | 0o120 | 80  | 0x50 | P   |     |    |                               |
| 0b101_0001 | 0o121 | 81  | 0x51 | Q   |     |    |                               |
| 0b101_0010 | 0o122 | 82  | 0x52 | R   |     |    |                               |
| 0b101_0011 | 0o123 | 83  | 0x53 | S   |     |    |                               |
| 0b101_0100 | 0o124 | 84  | 0x54 | T   |     |    |                               |
| 0b101_0101 | 0o125 | 85  | 0x55 | U   |     |    |                               |
| 0b101_0110 | 0o126 | 86  | 0x56 | V   |     |    |                               |
| 0b101_0111 | 0o127 | 87  | 0x57 | W   |     |    |                               |
| 0b101_1000 | 0o130 | 88  | 0x58 | X   |     |    |                               |
| 0b101_1001 | 0o131 | 89  | 0x59 | Y   |     |    |                               |
| 0b101_1010 | 0o132 | 90  | 0x5A | Z   |     |    |                               |
| 0b101_1011 | 0o133 | 91  | 0x5B | \[  |     |    |                               |
| 0b101_1100 | 0o134 | 92  | 0x5C | \   |     |    |                               |
| 0b101_1101 | 0o135 | 93  | 0x5D | ]   |     |    |                               |
| 0b101_1110 | 0o136 | 94  | 0x5E | ^   |     |    |                               |
| 0b101_1111 | 0o137 | 95  | 0x5F | _   |     |    |                               |
| 0b110_0000 | 0o140 | 96  | 0x60 | `   |     |    |                               |
| 0b110_0001 | 0o141 | 97  | 0x61 | a   |     |    |                               |
| 0b110_0010 | 0o142 | 98  | 0x62 | b   |     |    |                               |
| 0b110_0011 | 0o143 | 99  | 0x63 | c   |     |    |                               |
| 0b110_0100 | 0o144 | 100 | 0x64 | d   |     |    |                               |
| 0b110_0101 | 0o145 | 101 | 0x65 | e   |     |    |                               |
| 0b110_0110 | 0o146 | 102 | 0x66 | f   |     |    |                               |
| 0b110_0111 | 0o147 | 103 | 0x67 | g   |     |    |                               |
| 0b110_1000 | 0o150 | 104 | 0x68 | h   |     |    |                               |
| 0b110_1001 | 0o151 | 105 | 0x69 | i   |     |    |                               |
| 0b110_1010 | 0o152 | 106 | 0x6A | j   |     |    |                               |
| 0b110_1011 | 0o153 | 107 | 0x6B | k   |     |    |                               |
| 0b110_1100 | 0o154 | 108 | 0x6C | l   |     |    |                               |
| 0b110_1101 | 0o155 | 109 | 0x6D | m   |     |    |                               |
| 0b110_1110 | 0o156 | 110 | 0x6E | n   |     |    |                               |
| 0b110_1111 | 0o157 | 111 | 0x6F | o   |     |    |                               |
| 0b111_0000 | 0o160 | 112 | 0x70 | p   |     |    |                               |
| 0b111_0001 | 0o161 | 113 | 0x71 | q   |     |    |                               |
| 0b111_0010 | 0o162 | 114 | 0x72 | r   |     |    |                               |
| 0b111_0011 | 0o163 | 115 | 0x73 | s   |     |    |                               |
| 0b111_0100 | 0o164 | 116 | 0x74 | t   |     |    |                               |
| 0b111_0101 | 0o165 | 117 | 0x75 | u   |     |    |                               |
| 0b111_0110 | 0o166 | 118 | 0x76 | v   |     |    |                               |
| 0b111_0111 | 0o167 | 119 | 0x77 | w   |     |    |                               |
| 0b111_1000 | 0o170 | 120 | 0x78 | x   |     |    |                               |
| 0b111_1001 | 0o171 | 121 | 0x79 | y   |     |    |                               |
| 0b111_1010 | 0o172 | 122 | 0x7A | z   |     |    |                               |
| 0b111_1011 | 0o173 | 123 | 0x7B | {   |     |    |                               |
| 0b111_1100 | 0o174 | 124 | 0x7C |     |     |    |                               |
| 0b111_1101 | 0o175 | 125 | 0x7D | }   |     |    |                               |
| 0b111_1110 | 0o176 | 126 | 0x7E | ~   |     |    |                               |
| 0b111_1111 | 0o177 | 127 | 0x7F | DEL | ^?  |    | Delete                        |

ASCII literals are delimited by matching single quotes. The backslash character is used to escape characters that are unprintable or otherwise have special meaning, such as a newline, backslash itself, or the single quote character.

### 2.8.4 String interpolation

String interpolation uses square brackets: **`[]`**.

    name = "Tungsten"
    puts "Hello [name]"

### 2.8.5 String literal concatenation

Multiple adjacent string literals (delimited by whitespace) are allowed, and their meaning is the same as their concatenation. Thus, `"hello" "world"` is equivalent to `"helloworld"`. This feature can be used to split long strings or to add comments to parts of strings.

Note: although this feature is defined at the syntactic level, it is implemented at compile time. The "+" operator must be used to concatenate string expressions at run time.

### 2.8.6 Here documents

    HereDocument         = "<<-" NAME ... NAME .
    IndentedHereDocument = "<<~" NAME ... NAME .

### 2.8.7 ByteStrings

A Tungsten ByteString represents a sequence of bytes and is described by the following lexical definition:

    Hex               = "0"…"9" | "A"…"F" | "a"…"f" .
    LiteralByteString = "<<" [Hex Hex] { "," Hex Hex } ">>" .

Example:

    <<84,117,110,103,115,116,101,110>>

### 2.8.8 Symbols

A Tungsten Symbol represents a named token. They allow for Ruby-like DSLs.

    Letter = "a"…"z" .
    Digit  = "0"…"9" .
    LiteralSymbol = ":" Letter { Letter | Digit | "_" } .

Because strings in Tungsten are immutable, symbols are less useful than in Ruby.

## 2.9 Numeric literals

There are 4 types of numeric literals: integers, decimals, floating point numbers, and imaginary numbers. There are no complex literals (complex numbers can be formed by adding a real number and an imaginary number).

Note that numeric literals do not include a sign; a phrase like `−1` is actually an expression composed of the unary operator `-` and the literal `1`.

### 2.9.1 Integers

Integer literals are described by the following lexical definitions:

    Integer       = IntegerBase2 | IntegerBase8 | IntegerBase10 | IntegerBase16 | IntegerBase20 .

    DigitBase2    = "0"…"1" .
    DigitBase8    = "0"…"7" .
    DigitBase10   = "0"…"9" .
    DigitBase16   = "0"…"9" | "a"…"f" | "A"…"F" .
    DigitBase20   = "0"…"9" | "a"…"j" | "A"…"J" .

    IntegerBase2  = "0b" DigitBase2   { ["_"] DigitBase2  } .
    IntegerBase8  = "0o" DigitBase8   { ["_"] DigitBase8  } .
    IntegerBase10 =      DigitBase10  { ["_"] DigitBase10 } .
    IntegerBase16 = "0x" DigitBase16  { ["_"] DigitBase16 } . # Unsigned integers
    IntegerBase20 = "0v" DigitBase20  { ["_"] DigitBase20 } .

There is no limit for the length of integer literals apart from what can be stored in available memory.

Numerical constants can contain underscores for readability. Integers can be created as decimal (no prefix),
binary (`0b`), octal (`0o`), and hexadecimal (`0x`).

Note: non-zero decimal literals _may_ have leading zeros, as the octal literals have the `0o` prefix.
Note: leading and trailing underscores are not allowed.

Unsigned literals are described by the following lexical definitions:

    Hex     = "0"…"9" | "A"…"F" | "a"…"f" .

    Int8U   = "0x" Hex .
    Int16U  = "0x" Hex Hex .
    Int32U  = "0x" Hex Hex Hex Hex .
    Int64U  = "0x" Hex Hex Hex Hex ["_"] Hex Hex Hex Hex .
    Int128U = "0x" Hex Hex Hex Hex ["_"] Hex Hex Hex Hex ["_"] Hex Hex Hex Hex ["_"] Hex Hex Hex Hex .

    # Should "0b" and "0o" literals also be unsigned?

#### Integer Types

| Type    | Signed? | Bits | Min value | Max value |
| ------- | :-----: | ---- | --------- | --------- |
| Int8    | ✓       | 8    | −2⁷       | 2⁷   − 1  |
| Int8U   |         | 8    | 0         | 2⁸   − 1  |
| Int16   | ✓       | 16   | −2¹⁵      | 2¹⁵  − 1  |
| Int16U  |         | 16   | 0         | 2¹⁶  − 1  |
| Int32   | ✓       | 32   | −2³¹      | 2³¹  − 1  |
| Int32U  |         | 32   | 0         | 2³²  − 1  |
| Int64   | ✓       | 64   | −2⁶³      | 2⁶³  − 1  |
| Int64U  |         | 64   | 0         | 2⁶⁴  − 1  |
| Int128  | ✓       | 128  | −2¹²⁷     | 2¹²⁷ − 1  |
| Int128U |         | 128  | 0         | 2¹²⁸ − 1  |
|         |         |      |           |           |
| BigInt  | ✓       | ∞    | −∞        | ∞         |

The default type for an integer literal is 64-bits:

    wit> 1.class
    Int64

Unsigned integers are input and output using the `0x` prefix and hexadecimal (base 16) digits `0–9a–f` (the capitalized digits `A–F` also work). The size of the unsigned value is determined by the number of hex digits used:

    wit> 0x1.class
    Int8U

    wit> 0x123.class
    Int16U

    wit> 0x1234567.class
    Int32U

    wit> 0x123456789abcdef.class
    Int64U

This behavior is based on the observation that when one uses unsigned hex literals for integer values, one typically is using them to represent a fixed numeric byte sequence, rather than just an integer value.

Binary and octal literals are also supported:

    wit> 0b10
    0x02

    wit> 0b10.class
    Int8U

    wit> 0o10
    0x08

    wit> 0o10.class
    Int8U

The minimum and maximum representable values of primitive numeric types such as integers are given by the `min/0` and `max/0` methods:

    # wit> (Int32: min max)
    # wit> Int32{min max}
    wit> (Int32.min, Int32.max)
    (−2147483648, 2147483647)

    wit> [Int8, Int16, Int32, Int64, Int128, Int8U, Int16U, Int32U, Int64U, Int128U].each do |type|
           puts "[type.lpad(7)]: ([type.min], [type.max])"

       Int8: (-128, 127)
      Int16: (-32768, 32767)
      Int32: (-2147483648, 2147483647)
      Int64: (-9223372036854775808, 9223372036854775807)
     Int128: (-170141183460469231731687303715884105728, 170141183460469231731687303715884105727)
      UInt8: (0, 255)
     UInt16: (0, 65535)
     UInt32: (0, 4294967295)
     UInt64: (0, 18446744073709551615)
    UInt128: (0, 340282366920938463463374607431768211455)

The values returned by `min/0` and `max/0` are always of the receiver's type.

### 2.9.2 Decimals

Decimal literals (or rationals) are described by the following lexical definitions:

    (* @todo Roman numeral characters U+2160–217F, counting rods U+1D360 to U+1D37F *)

    Digit      = "0"…"9" . 
    Letter     = "\p{letter}" .
    Letters    = Letter { Letter | "_" } .
    Currency   = "\p{currency symbol}" .
    SuperNZ    =       "¹" | "²" | "³" | "⁴" | "⁵" | "⁶" | "⁷" | "⁸" | "⁹" .
    Super      = "⁰" | "¹" | "²" | "³" | "⁴" | "⁵" | "⁶" | "⁷" | "⁸" | "⁹" .
    Supers     = ["⁻" | "⁺"] SuperNZ { Super } .

    Prefix     = Currency .
    Suffix     = Units | Degrees | Percents .

    Unit       = (Letters ["-" Letters] | [Letters] "/" Letters) [ "^" Exponent | Supers ] .
    Units      = ["⋅"] Unit { "⋅" Unit } .
    Degrees    = "℃" | "℉" | "°C" | "°F" | "°" [Letter] .
    Percents   = "%" | "‰" | "‱" | "٪" | "؉" | "؊" | "﹪" | "％" | "percent" .

    Exponent   = ["+" | "-" | "−"] Digits .

    Scientific = "x10^" Exponent
               | "×10^" Exponent
               | "x10"  Supers
               | "×10"  Supers
               | "e"    Exponent
               | "E"    Exponent
               .

    Precision  = "±" Digits ["." Digits]
               | "±" Digits "/" Digits
               | "(" Digits ")"
               .

    Digits     = Digit { Digit | "_" } .

    Decimal    = [Prefix] Digits  "." Digits  [Precision]            [Suffix]
               | [Prefix] Digits  "/" Digits  [Precision]            [Suffix]
               | [Prefix] Digits              [Precision]             Suffix
               |  Prefix  Digits              [Precision]            [Suffix]
               | [Prefix] Digits ["." Digits] [Precision] Scientific [Suffix]
               .

    Literal    = Decimal " "
               | "ℎ" (* Planck's constant *)
               | "ℏ" (* Reduced Planck constant *)
               | "ℇ" (* Eulers constant, irrational *)
               | "π" (* Pi, irrational *)
               | "ϕ" (* Phi, irrational *)
               .

Tungsten decimal literals can be annotated with semantic meaning that is available at run-time:

* units of measurement (available at run-time)
* precision (or error)
* currency
* percents

Tungsten allows you to create new units of measurement, auto-generating the conversions to other units.

Tungsten ships with all dimensions from the International System of Units, abbreviated SI from the French _Le **S**ystème **I**nternational d'Unités_.

Example: literal definition of Planck's constant: `ℎ = 6.626_069_57(29)×10²³J·s`.

_Note: Trailing zeros are meaningful, as they indicate the precision associated with the number. Decimal literals will be normalized to a standard form before returned: e.g., "x10^2" => "×10²"._

<!-- @todo: multiplicative conversions vs. additive: ft -> m vs. C -> F -->
<!-- @todo: distance between two points on a sphere: http://www.johndcook.com/fsharp_longitude_latitude.html -->

<!-- @todo: make this work f = (x)-> 2x + 3x² - 8; assert f(2) == 8 -->

<!-- https://github.com/KarolS/units -->

Decimal literals can be defined with semantic meaning:

    0.000_000_000_1
    0.08
    0.0800

    wit> 22/7
      => 22/7

    wit> 22/2
      => 11

    wit> $3.50 - 25¢
      => $3.25

    wit> $499 - 15%          # woah, same as $499 * 0.85
      => $424.15

    wit> 20% - 15%
      => 5%

    wit> 1cm * 1cm * 1cm
      => 1mL

    wit> 10ft * 10ft
      => 100sqft

    wit> 1ft + 12inches
      => 2ft

    wit> 2ft.to_s
      => "2 feet"

    wit> 299_792_458m/s

    wit> 10ft·lbs

    wit> 2m + 2lbs
    error UnitMismatch

    wit> 3ft - 1m
      => -3+3/8inches

    wit> 73/100±1/100

    wit> 1.602_176_487(40)x10^-19C
    wit> 1.602_176_487±0.000_000_040x10^-19C

    wit> V = (1kg * 1m^2) / (1amp * 1s^3)

    wit> 100MV # megavoltage of lightning

    wit> rate = 1/s

    wit> 40°20′50″

    wit> 3′5″ # 3 feet 5 inches (of length), or 3 minutes and 5 seconds (of time)
    wit> 3m5s

    wit> ℎ
      => 6.626_069_57(29)×10²³J·s

    wit> ℏ
      => 1.054_571_726(47)×10³⁴J·s

    # exact calculations using irrational numbers
    wit> 2π - 1π - 1π
      => 0

    wit> 3π / 2
      => 1.5π

    wit> 512GiB %% bytes
      => 549_755_813_888·bytes

    Tungsten.register_unit "km", alias: "kilometer",     equals: 1000m
    Tungsten.register_unit "cm", alias: "centimeter",    equals: 1m⁻²
    Tungsten.register_unit "in", aliases: ["inch", "\N[DOUBLE PRIME]"], equals: 2.54cm, as: "inch"

#### SI Base Units <small>(meter kilogram second)</small>

| Name     | Abbr | Measure                   |
| -------- | ---- | ------------------------- |
| metre    | m    | length                    |
| kilogram | kg   | mass                      |
| second   | s    | time                      |
| ampere   | A    | electric current          |
| kelvin   | K    | thermodynamic temperature |
| mole     | mol  | amount of substance       |
| candela  | cd   | luminous intensity        |

_Note: The kilogram is the only prefixed SI Base Unit. The prefixes for mass refer to the gram as their base._

#### CGS Base Units <small>(centimeter gram second)</small>

| Name                  | Abbr  | Measure             |
| --------------------- | ----- | ------------------- |
| centimeter            | cm    | length              |
| gram                  | g     | mass                |
| second                | s     | time                |
| centimeter per second | cm/s  | velocity            |
| gal                   | Gal   | acceleration        |
| dyne                  | dyn   | force               |
| erg                   | erg   | energy              |
| erg per second        | erg/s | power               |
| barye                 | Ba    | pressure            |
| poise                 | P     | dynamic viscosity   |
| stokes                | St    | kinematic viscosity |
| kayser                | cm⁻¹  | wavenumber          |

<small>Source: [wikipedia.org/wiki/CGS](http://en.wikipedia.org/wiki/CGS)</small>

#### Significant figures

A significant figure is a digit in a number that adds to its precision. This includes all nonzero numbers, zeroes between significant digits, and zeroes indicated to be significant. Leading and trailing zeroes are not significant because they exist only to show the scale of the number. Therefore, 1,230,400 has five significant figures—1, 2, 3, 0, and 4; the two zeroes serve only as placeholders and add no precision to the original number.

When a number is converted into normalized scientific notation, it is scaled down to a number between 1 and 10. All of the significant digits remain, but all of the place holding zeroes are incorporated into the exponent. Following these rules, 1,230,400 becomes 1.2304 x 10⁶.

##### Ambiguity of the last digit

It is customary in scientific measurements to record all the significant digits from the measurements, and to guess one additional digit if there is any information at all available to the observer to make a guess. The resulting number is considered more valuable than it would be without that extra digit, and it is considered a significant digit because it contains some information leading to greater precision in measurements and in aggregations of measurements (_e.g._, when adding them or multiplying them together).

Additional information about precision can be conveyed through additional notations. In some cases, it may be useful to know how exact the final significant digit is. For instance, the accepted value of the unit of elementary charge can properly be expressed as 1.602_176_487(40)x10^-19C, which is shorthand for 1.602_176_487±0.000_000_040x10^-19C.

#### Metric prefixes

| Prefix | Symbol | 1000<sup>m</sup>    | 10<sup>n</sup> | Decimal                           | English word | Since |
| ------ | :----: | ------------------- | -------------- | --------------------------------: | ------------ | :---: |
| yotta  | Y      | 1000⁸               | 10²⁴           | 1 000 000 000 000 000 000 000 000 | septillion   | 1991  |
| zetta  | Z      | 1000⁷               | 10²¹           | 1 000 000 000 000 000 000 000     | sextillion   | 1991  |
| exa    | E      | 1000⁶               | 10¹⁸           | 1 000 000 000 000 000 000         | quintillion  | 1975  |
| peta   | P      | 1000⁵               | 10¹⁵           | 1 000 000 000 000 000             | quadrillion  | 1975  |
| tera   | T      | 1000⁴               | 10¹²           | 1 000 000 000 000                 | trillion     | 1960  |
| giga   | G      | 1000³               | 10⁹            | 1 000 000 000                     | billion      | 1960  |
| mega   | M      | 1000²               | 10⁶            | 1 000 000                         | million      | 1960  |
| kilo   | k      | 1000¹               | 10³            | 1 000                             | thousand     | 1795  |
| hecto  | h      | 1000<sup>2/3</sup>  | 10²            | 1 00                              | hundred      | 1795  |
| deca   | da     | 1000<sup>1/3</sup>  | 10¹            | 1 0                               | ten          | 1795  |
|        |        | 1000⁰               | 10⁰            | 1                                 | one          | -     |

| Prefix | Symbol | 1000<sup>m</sup>    | 10<sup>n</sup> | Decimal                           | English word  | Since |
| ------ | :----: | ------------------- | -------------- | :-------------------------------- | ------------- | :---: |
|        |        | 1000⁰               | 10⁰            | 1                                 | one           | -     |
| deci   | d      | 1000<sup>-1/3</sup> | 10⁻¹           | 0.1                               | tenth         | 1795  |
| centi  | c      | 1000<sup>-2/3</sup> | 10⁻²           | 0.01                              | hundredth     | 1795  |
| milli  | m      | 1000⁻¹              | 10⁻³           | 0.001                             | thousandth    | 1795  |
| micro  | µ, mc  | 1000⁻²              | 10⁻⁶           | 0.000 001                         | millionth     | 1960  |
| nano   | n      | 1000⁻³              | 10⁻⁹           | 0.000 000 001                     | billionth     | 1960  |
| pico   | p      | 1000⁻⁴              | 10⁻¹²          | 0.000 000 000 001                 | trillionth    | 1960  |
| femto  | f      | 1000⁻⁵              | 10⁻¹⁵          | 0.000 000 000 000 001             | quadrillionth | 1964  |
| atto   | a      | 1000⁻⁶              | 10⁻¹⁸          | 0.000 000 000 000 000 001         | quitillionth  | 1964  |
| zepto  | z      | 1000⁻⁷              | 10⁻²¹          | 0.000 000 000 000 000 000 001     | sextillionth  | 1991  |
| yocto  | y      | 1000⁻⁸              | 10⁻²⁴          | 0.000 000 000 000 000 000 000 001 | septillionth  | 1991  |

Note: dag,dkg: decagram, mcg: microgram, megagram: tonne (t), megatonne or megaton -> teragram (Tg)

#### Binary prefixes

| Prefix | Symbol | 2<sup>n</sup> | Derivation    | Decimal                           |
| ------ | ------ | ------------- | ------------- | --------------------------------- |
| kibi   | Ki     | 2¹⁰           | kilo:  (10³)¹ | 1 024                             |
| mebi   | Mi     | 2²⁰           | mega:  (10³)² | 1 048 576                         |
| gibi   | Gi     | 2³⁰           | giga:  (10³)³ | 1 073 741 824                     |
| tebi   | Ti     | 2⁴⁰           | tera:  (10³)⁴ | 1 099 511 627 776                 |
| pebi   | Pi     | 2⁵⁰           | peta:  (10³)⁵ | 1 125 899 906 842 624             |
| exbi   | Ei     | 2⁶⁰           | exa:   (10³)⁶ | 1 152 921 504 606 846 976         |
| zebi   | Zi     | 2⁷⁰           | zetta: (10³)⁷ | 1 180 591 620 717 411 303 424     |
| yobi   | Yi     | 2⁸⁰           | yobi:  (10³)⁸ | 1 208 925 819 614 629 174 706 176 |

### 2.9.3 Floating points

Floating point literals are described by the following lexical definitions:

    Digit    = "0"…"9" .
    Digits   = Digit { ["_"] Digit } .
    Float    = "~" Digits ["." Digits] Exponent .
    Exponent = ("e" | "E") ["+" | "-" | "−"] Digit { Digit } .

#### Floating-point Types

| Type     | Precision | Bits | IEEE 754  | sn | exp | sig |
| -------  | --------- | ---- | --------- | -- | --- | --- |
| Float16  | half      | 16   | binary16  | 1  | 5   | 11  |
| Float32  | single    | 32   | binary32  | 1  | 8   | 23  |
| Float64  | double    | 64   | binary64  | 1  | 11  | 52  |
| Float128 | quad      | 128  | binary128 | 1  | 15  | 112 |
| Float256 | octuple   | 256  | binary256 | 1  | 19  | 236 |

[IEEE 754](https://en.wikipedia.org/wiki/IEEE_754)
[IEEE 754 Standard](https://standards.ieee.org/ieee/754/)

#### Floating-point zero

Floating-point numbers have [two zeros](http://en.wikipedia.org/wiki/Signed_zero), positive zero
and negative zero. They are equal to each other but have different binary representations.

    wit> ~+0.0e0 == ~-0.0e0
    true

    wit> ~+0.0e0.bits
    "0000000000000000000000000000000000000000000000000000000000000000"

    wit> ~-0.0e0.bits
    "1000000000000000000000000000000000000000000000000000000000000000"

    wit> ~210.0e0
    ~2.1e2

#### Special floating-point values

There are three specified standard floating-point values that do not correspond to any point on the real number line:

| Float16 | Float32 | Float64  | Float128 | Float256 | Name              | Description                                                      |
| ------- | ------- | -------- | -------- | -------- | ----------------- | ---------------------------------------------------------------- |
| Inf16   | Inf32   | Inf, ∞   | Inf128   | Inf256   | positive infinity | A value greater than all finite floating-point values            |
| −Inf16  | −Inf32  | −Inf, −∞ | -Inf128  | -Inf256  | negative infinity | A value less than all finite floating-point values               |
| NaN16   | NaN32   | NaN      | NaN128   | NaN256   | not a number      | A value not equal to any floating-point value (including itself) |

For further discussion of how these non-finite floating-point values are ordered with respect to each other and other floats, see [Numeric Comparisons](http://www.google.com). By the [IEEE 754 standard][IEEE 754], these floating-point values are the results of certain arithmetic operations.

    wit> 1 / Inf
    ~0.0e0

    wit> ~1.0 / 0
    Inf

    wit> −~1.0 / 0
    −Inf

    wit> ~0.1 / 0
    Inf

    wit> ~0.0 / 0
    NaN

    wit> ~1.0 + Inf
    Inf

    wit> ~1.0 − Inf
    −Inf

    wit> Inf + Inf
    Inf

    wit> Inf − Inf
    NaN

    wit> Inf * Inf
    Inf

    wit> Inf / Inf
    NaN

    wit> ~0.0 * Inf
    NaN

The `#min` and `#max` methods are available for floating-point types:

    wit> (Float16.min, Float16.max)
    (−Inf16, Inf16)

    wit> (Float32.min, Float32.max)
    (−Inf32, Inf32)

    wit> (Float64.min, Float64.max)
    (−Inf, Inf)
    (−∞, ∞)

[IEEE 754]: http://en.wikipedia.org/wiki/IEEE_floating_point

#### Machine epsilon

Most real numbers cannot be represented exactly with floating-point numbers, and so for many purposes it is important to know the distance between two adjacent representable floating-point numbers, which is often known as [machine epsilon](http://en.wikipedia.org/wiki/Machine_epsilon).

Tungsten provides `.eps`, which gives the distance between `1.0` and the next larger representable floating-point value:

    wit> Float32.eps
    ~1.1920929e-7

    wit> Float64.eps
    ~2.220446049250313e-16

These values are `~2.0^-23` and `~2.0^-52` as `Float32` and `Float64` values, respectively. The `#eps` method is also available on instances of floating-point numbers and gives the absolute difference between that value and the next representable floating-point value. That is, `x.eps` yields a value of the same type as `x` such that `x + x.eps` is the next representable floating-point value larger than `x`:

    wit> ~1.0.eps
    ~2.220446049250313e-16

    wit> ~1000.0.eps
    ~1.1368683772161603e-13

    wit> ~1e-27.eps
    ~1.793662034335766e-43

    wit> ~0.0.eps
    ~5.0e-324

The distance between two adjacent representable floating-point values is not constant, but is smaller for smaller values and larger for larger values. In other words, the representable floating-point numbers are densest in the real number line near zero, and grow sparser exponentially as one moves farther away from zero. By definition, `1.0.eps` is the same as `Float64.eps` since `1.0` is a 64-bit floating-point value.

Tungsten also provides the `#next` and `#prev` methods which return the next larger or smaller representable floating-point number to the receiver, respectively:

    wit> x = ~1.25e0
    ~1.25e0

    wit> x.next
    ~1.2500001e0

    wit> x.prev
    ~1.2499999e0

    wit> x.prev.bits
    "00111111100111111111111111111111"

    wit> x.bits
    "00111111101000000000000000000000"

    wit> x.next.bits
    "00111111101000000000000000000001"

This example highlights the general principal that the adjacent representable floating-point numbers also have adjacent binary integer representations.

#### Rounding modes

If a number doesn't have an exact floating-point representation, it must be rounded to an appropriate representable value, however, if wanted, the manner in which this rounding is done can be changed according to the rounding modes presented in the [IEEE 754 standard][IEEE 754]:

    wit> ~1.1e0 + ~1.0e-1
    ~1.2000000000000002

    wit> with_rounding(Float64, :round_down) -> ~1.1e0 + ~1.0e-1
    ~1.2

The default mode used is always `:round_nearest`, which rounds to the nearest representable value, with ties rounded towards the nearest value with an even least significant bit.

#### Background and References

Floating-point arithmetic entails many subtleties which can be surprising to users who are unfamiliar with the low-level implementation details. However, these subtleties are described in detail in most books on scientific computation, and also in the following references:

* The definitive guide to floating-point arithmetic is the _[IEEE 754 Standard](https://standards.ieee.org/ieee/754/)_; however, it is not available for free online.
* For a brief but lucid presentation of how floating-point numbers are presented, see John D. Cook's [floating-point articles](https://www.johndcook.com/blog/tag/floating-point/) on the subject.
* Also recommended is Bruce Dawson's [series of blog posts](https://randomascii.wordpress.com/category/floating-point/) on floating-point numbers.
* For an excellent, in-depth discussion of floating-point numbers and issues of numerical accuracy encountered when computing with them, see David Goldberg's paper _[What Every Computer Scientist Should Know About Floating-Point Arithmetic](http://citeseerx.ist.psu.edu/viewdoc/download?doi=10.1.1.102.244&rep=rep1&type=pdf)_.
* For even more extensive documentation of the history of, rationale for, and issues with floating-point numbers, as well as discussion of many other topics in numerical computing, see the [collected writings](http://www.cs.berkeley.edu/~wkahan/) of [William Kahan](http://en.wikipedia.org/wiki/William_Kahan), commonly known as the "Father of Floating-Point". Of particular interest may be _[An Interview with the Old Man of Floating-Point](http://www.cs.berkeley.edu/~wkahan/ieee754status/754story.html)_.

### 2.9.4 Imaginary literals

Imaginary literals are described by the following lexical definitions:

    Imaginary = Float "i" .

An imaginary literal yields a complex number with a real part of 0.0. Complex numbers are represented
as a pair of floating point numbers and have the same restrictions on their range. To create a
complex number with a nonzero real part, add a floating point number to it, _e.g._, `(3 + 4i)`.

### 2.9.5 Literal zero and one

Tungsten provides methods which return literal 0 and 1 corresponding to a specified type or the type of a given variable.

    | Method | Description                                      |
    | ------ | ------------------------------------------------ |
    | x.zero | Literal zero of type `x` or type of variable `x` |
    | x.one  | Literal one of type `x` or type of variable `x`  |

Examples:

    wit> Float32.zero
    ~0.0e0

    wit> ~1.0.zero
    ~0.0

    wit> Int32.one
    1

    wit> BigFloat.one
    ~1e+00 with 256 bits of precision

## 2.10 Temporal, network, and structured literals

Besides strings and numbers, the lexer recognizes several families of _domain literals_ — colors, dates, network addresses, and durations — each as a single token that yields a value of a dedicated built-in type. Because these forms overlap syntactically with comments, subtraction, and method chains, the lexer disambiguates them by strict adjacency (no interior spaces) and, in most cases, by digit count.

_Note: The reference interpreter is the authoritative implementation of these literals. The self-hosted native compiler recognizes the common cases but does not yet lex every form — MAC addresses, microsecond and ISO-8601 durations, and the fully-expanded (non-`::`) IPv6 form are reference-interpreter-only — and it validates digit counts and octet ranges without range-checking calendar or clock fields. Divergences are noted per form below._

### 2.10.1 Color literals

A color literal is a `#` immediately followed by exactly three, four, six, or eight hexadecimal digits, and not followed by a further hexadecimal digit or identifier character.

    Hex   = "0"…"9" | "a"…"f" | "A"…"F" .
    Color = "#" ( Hex Hex Hex
                | Hex Hex Hex Hex
                | Hex Hex Hex Hex Hex Hex
                | Hex Hex Hex Hex Hex Hex Hex Hex ) .

The three- and four-digit forms are _shorthand_: each nibble is doubled (`#RGB` becomes `#RRGGBB`, `#RGBA` becomes `#RRGGBBAA`). Six digits are `RRGGBB`; eight are `RRGGBBAA`. A literal with no alpha channel is fully opaque (α = 255).

    #FF0000       # => Color [255, 0, 0, 255]
    #F00          # => Color [255, 0, 0, 255]   shorthand
    #FF000080     # => Color [255, 0, 0, 128]   with alpha
    #F008         # => Color [255, 0, 0, 136]   shorthand with alpha

Because a color begins with `#` — the comment character (§2.5) — the two are told apart by what follows: a run of exactly 3, 4, 6, or 8 hexadecimal digits _not_ glued to further word characters is a color; every other `#…` is a comment. Thus `#FF` (two digits) and `#FFFFF` (five) are comments, and `#FF0000abcd` is a comment because the trailing letters run past eight hex digits.

Token: `COLOR`. Runtime type: `Color`.

### 2.10.2 Date and month literals

A date literal is a four-digit year, a hyphen, and then either a two-digit month with a two-digit day (a calendar date) or a three-digit ordinal day-of-year.

    Year    = Digit Digit Digit Digit .
    Month   = Digit Digit .
    Day     = Digit Digit .
    Ordinal = Digit Digit Digit .
    Date    = Year "-" ( Month "-" Day | Ordinal ) .
    MonthOf = Year "-" Month .                # no day component

    YYYY-MM-DD    # => Date     calendar date
    YYYY-DDD      # => Date     ordinal day-of-year
    YYYY-MM       # => Month    year and month

A year followed by `-` and a two-digit month but no `-DD` yields a `Month` value rather than a `Date`.

**Disambiguation from subtraction.** The date scanner fires only when each hyphen is immediately adjacent to the digits on both sides. `YYYY-MM-DD` is a date; `YYYY - MM - DD`, with spaces around the operators, is integer subtraction (§2.3).

_Compiler divergence: the reference interpreter range-checks the fields (months `01`–`12`, days `01`–`31`, ordinals `001`–`366`) and additionally accepts ISO week dates such as `YYYY-Www-D`; the native compiler checks only digit counts, so it accepts an out-of-range date like `YYYY-99-99`._

Token: `DATE`, or `MONTH` for the day-less form. Runtime types: `Date`, `Month`.

### 2.10.3 DateTime literals

A datetime literal is a calendar date, the letter `T`, and a time. Hours and minutes are required; seconds, fractional seconds, and a timezone are optional.

    Time     = Hour ":" Minute [ ":" Second [ "." Fraction ] ] [ Zone ] .
    Zone     = "Z" | ( "+" | "-" ) Hour [ ":" Minute ] .
    DateTime = Date "T" Time .

    YYYY-MM-DDT14:30            # date and time, no zone
    YYYY-MM-DDT14:30:00Z        # UTC
    YYYY-MM-DDT09:00:00-08:00   # with offset
    YYYY-MM-DDT14:30:00.500+05:30

_Compiler divergence: the reference interpreter range-checks the clock fields (hours `00`–`23`, minutes `00`–`59`, seconds `00`–`60` for leap seconds), caps fractional seconds at three digits, and accepts the `24:00` end-of-day form; the native compiler checks only digit counts on the time and leaves the fraction unbounded._

Token: `DATETIME`.

### 2.10.4 IP-address literals

An IPv4 literal is four dot-separated octets, each in the range 0–255, with an optional `:port` (0–65535).

    Octet = Digit [ Digit [ Digit ] ] .       # value 0…255
    Port  = Digits .                          # value 0…65535
    IPv4  = Octet "." Octet "." Octet "." Octet [ ":" Port ] .

    192.168.1.1
    10.0.0.1:8080     # with port
    255.255.255.0

The IPv4 scanner runs before the floating-point path: a one-to-three-digit integer ≤ 255 immediately followed by `.` and a digit begins an address attempt, which succeeds only when exactly four octets are present. A three-part form such as `1.2.3` therefore backtracks to a decimal `1.2` followed by `.3` (see §2.10.8).

Both engines also recognize IPv6 literals ([RFC 5952](https://www.rfc-editor.org/rfc/rfc5952)) in `::`-compressed form (`::1`, `2001:db8::1`, bare `::`) and the IPv4-mapped form (`::ffff:1.2.3.4`); the native compiler prints them fully expanded (`::1` → `0:0:0:0:0:0:0:1`). Per RFC 5952 §4.3 an IPv6 literal must be **lowercase**: `fe80::1` is an address, `FE80::1` is not — reserving an uppercase leading letter for class references (`Tungsten:JSON`). An IPv6 literal also never follows a word character, so `Foo::Bar` stays a name/scope form, not an address. Reference-interpreter-only: the fully-expanded *input* form with no `::` (`2001:db8:0:0:0:0:0:1`) — which the compiler leaves as colon-separated fragments to avoid mis-lexing hash keys and namespaces — plus zone identifiers, bracketed-with-port forms, and MAC addresses.

Token: `IP4` / `IP6`. Runtime types: `IPv4`, `IPv6`.

### 2.10.5 CIDR literals

A CIDR literal is an IPv4 address, a slash, and a prefix length of 0–32.

    CIDR = IPv4 "/" Prefix .                   # Prefix 0…32

    10.0.0.0/8
    192.168.0.0/24
    0.0.0.0/0

A prefix greater than 32 is not a CIDR; the `/prefix` is left as a division operator applied to the address.

Both engines also recognize IPv6 CIDR (`2001:db8::/32`, `::/0`, prefix 0–128) for the `::`-compressed address forms.

Token: `CIDR4` (reference-only `CIDR6`). Runtime type: `CIDR`.

### 2.10.6 Duration literals

A duration literal is a compact sequence of number-and-unit components in descending order of magnitude, drawn from `y`, `mo`, `w`, `d`, `h`, `m`, `s`, `ms`, and `ns`.

    Unit     = "y" | "mo" | "w" | "d" | "h" | "m" | "s" | "ms" | "ns" .
    Duration = ( Digits Unit ) { Digits Unit } .   # components largest to smallest

    5m30s        # 5 minutes, 30 seconds
    2h30m
    1y2mo3d
    500ms        # a single component is a duration only for ms, ns, mo

Two or more components always form a duration. A _single_ component whose unit is ambiguous with a unit-of-measurement (`y`, `w`, `d`, `h`, `m`, `s`) is instead a `Quantity` (§2.9.2); only the unambiguous single units `ms`, `ns`, and `mo` form a one-component duration. Components must be written from largest to smallest.

_Reference-interpreter-only: microsecond durations (`µs` / `μs`) and ISO-8601 durations (`P1Y2M3DT4H5M6S`, `PT1.5H`, `P3W`) are recognized by the reference lexer only._

Angle literals combining degrees, arcminutes, and arcseconds — `40°20′50″` — are _not_ recognized: `°` is a unit character (§2.9.2), but `′` and `″` are not lexed.

Token: `DURATION`. Runtime type: `Duration`.

### 2.10.7 UUID literals

A UUID literal is the canonical hyphenated 8-4-4-4-12 hexadecimal form, with a version nibble of 1–8 and an RFC 4122 variant nibble.

    Version = "1"…"8" .
    Variant = "8" | "9" | "a" | "A" | "b" | "B" .
    UUID    = Hex⁸ "-" Hex⁴ "-" Version Hex³ "-" Variant Hex³ "-" Hex¹² .

    550e8400-e29b-41d4-a716-446655440000

Both engines recognize UUID literals. A sequence that is not a valid UUID — wrong field lengths, or a version nibble outside 1–8 — is instead read as hexadecimal integers joined by `-` operators.

Token: `UUID`. Runtime type: `UUID`.

### 2.10.8 A note on version-like sequences

Tungsten has no version or semantic-version literal. A sequence such as `1.2.3` is read by the ordinary number machinery as a decimal `1.2` followed by `.3` (a call to member `3`), and cannot form an IPv4 address because that path requires four octets (§2.10.4).

## 2.11 Boolean literals

Tungsten represents boolean values with two objects literals: `true` and `false`.

    Boolean = True | False .
    True    = "true"  | "on"  | yes" .
    False   = "false" | "off" | "no" .

Token: `BOOLEAN`

## 2.12 Nil literal

The Nil type has only one possible value: `nil`.

    Nil = "nil" .

Token: `NIL`

## 2.13 Regular expression literals

    Regex = "/" Characters "/" .

Regular expressions participate in pattern matching through `=~` and through
regex arms in `case` expressions.

On a successful match, `$1`, `$2`, ... denote the corresponding parenthesized
capture groups. Capture variables are scoped to the same statement as the regex
literal that introduced the match. A newline or semicolon ends the
capture-variable lexical scope.

Examples:

    if /^--(.+)=(.+)$/ =~ arg then [$1.to_sym, $2]

    case arg
      /^--(.+)=(.+)$/ => [$1.to_sym, $2]

## 2.14 Collection literals

### 2.14.1 Tuples

Tungsten tuple literals are described by the following lexical definitions:

    Tuple = "(" Expression { "," Expression } ")" .

### 2.14.2 Arrays

Tungsten array literals are described by the following lexical definitions:

    Array = "[" Expression { "," Expression } "]" .

### 2.14.3 Hashes

Tungsten hash literals are described by the following lexical definitions:

    Hash  = "{" Pair { "," Pair } "}" .
    Pair  = Key ":" Expression | '"' Key '"' Space ":" Space Expression .
    Key   = .
    Space = " " { " " } .

Examples

    hash = { one: 1, two: 2 }
    hash = { "one" : 1, "two" : 2 }
    hash = {
      one: 1
      two: 2
    }

### 2.14.4 Sets

    Set = "<(" Expression { "," Expression } ")>" .

### 2.14.5 Multisets

    Multiset = "<{" Expression { "," Expression } "}>" .

### 2.14.6 Word and symbol arrays

Two percent-literal forms build arrays of short strings or symbols without quotes or commas. Only the `[ ]` delimiter is accepted, and elements are separated by whitespace (spaces, tabs, or newlines).

    WordArray   = "%w[" { Whitespace Word } Whitespace "]" .
    SymbolArray = "%i[" { Whitespace Word } Whitespace "]" .

    %w[red green blue]     # => ["red", "green", "blue"]
    %i[get post put]       # => [:get, :post, :put]

Multi-line forms are allowed, with newlines acting as separators. There is no escape mechanism, so an element cannot itself contain `]`.

## 2.15 Operators and delimiters

The following character sequences are operators and/or punctuation:

    . , ; : .. ... … ` ! @ # $ ? + - * / % ** // %% ^^ -- ++ ~~ && || ~ & | ^ <- -> => #-> #->>
    = == === !== != ≠ =~ !~ !~~ < > <= >= ≤ ≥ <=> += -= /= *= %= ^= &= |= ~= &&= ||=
    { } ( ) [ ] << >> <" "> <[ ]> <( )>
    → ←

Certain symbols serve more than one purpose in the grammar.

The augmented assignment operators, serve lexically as delimiters, but also perform an operation.

Any printing ASCII character not listed above as an operator, delimiter, or literal introducer is unused by Tungsten; its occurrence outside string literals and comments is an error.

A physical line is a sequence of characters terminated by an end-of-line sequence. In source files, any of the standard platform line termination sequences can be used – Unix (`LF`), Windows (`CR LF`), or the old Macintosh (`CR`). All line termination sequences can be used interchangeably, regardless of platform.
