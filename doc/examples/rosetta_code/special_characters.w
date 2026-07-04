characters<text>
  \0 U+0000 NULL
  \a U+0007 BEL
  \b U+0008 BACKSPACE
  \t U+0009 CHARACTER TABULATION
  \n U+000A LINE FEED
  \l U+000A LINE FEED
  \v U+000B LINE TABULATION
  \f U+000C FORM FEED
  \r U+000D CARRIAGE RETURN
  \c U+000D CARRIAGE RETURN
  \e U+001B ESCAPE
  \s U+0020 SPACE
  \" U+0022 QUOTATION MARK
  \' U+0027 APOSTROPHE
  \[ U+005B LEFT SQUARE BRACKET
  \\ U+005C REVERSE SOLIDUS
  [expression] INTERPOLATION
  \uxxxx Unicode character, by hex value
  \U{xx xxxx xxxxxx} 1 or more Unicode characters, by hex values
  \N{NAME 1, NAME 2} 1 or more Unicode characters, by names
  \P{prop=value}     1 or more Unicode characters, by property
  \x unescaped x

## expect skip currently unsupported in this runtime
