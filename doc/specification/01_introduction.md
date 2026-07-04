# Introduction

This is the specification for the Tungsten programming language.

It defines the syntax and semantics of the language, as well as the behavior of conforming implementations. It is intended to be a comprehensive reference for programmers and implementers of Tungsten.

Tungsten is a general-purpose, multi-paradigm language. It is highly opinionated and supports functional, imperative, and object-oriented patterns, with first-class support for concurrent programming.

Its grammar is compact by design, balancing comprehension against token economy, while remaining straightforward to parse by both humans and machines.

## Background and Goals

Tungsten grew out of frustration with informal specifications, ambiguous grammars, and design choices that make the generation of efficient code nearly impossible.

Tungsten is object-oriented: every value is an object. The type and behavior of an object is described by its class, and classes can be extended by composing traits.

Tungsten is functional: every function is a value, and every object is callable.

Tungsten aims to be both highly expressive - making programming productive and enjoyable - and to compile to efficient machine code.

Tungsten is designed from the ground up with a fully integrated object model, syntax, and control structures.

Tungsten owes an enormous debt to the languages that precede and inspire it. This is normally where one would quote Sir Isaac Newton; instead, here is a poem that echoes Tungsten's polyglot heritage:

> In the land where dreams
> and half-dreams lie,
> they destroyed the yellow wood
> while frost sat ired guarding paths
> unbound by passersby
>
> Born of weary midnights dreary
> wrought from cold unbroken heart,
> on shoulders of giants, yet dwarves
> beside late Ottmar & Descartes.
>
> Come sail across a Tungsten sea,
> and dream some dreams to tread with me.

<small><small>Note: According to xkcd, [Tungsten melts at 3422°C](http://what-if.xkcd.com/50/). Should you _actually_ happen upon a Tungsten sea, please do not attempt to sail across it.</small></small>

<!-- @todo: http://opendylan.org/books/drm/Background_and_Goals -->

## Source Character Set

    [space][newline]
    ()[]{}<>
    `'":;?
    .,~!@#$%=
    */-\+_|&^
    0123456789
  « abcdefghijklmnopqrstuvwxyz »
    ABCDEFGHIJKLMNOPQRSTUVWXYZ

    + all other Unicode characters

## Implementation

This document may make suggestions, but will not specify implementation details. Alternate Tungsten implementations may work differently.

_Note: At the time of this writing, the only known implementations of Tungsten are the Ruby interpreter and the bootstrapped interpreter/compiler._

## Notation

Example code fragments are presented in `typewriter face`:

    f = ->(x) 3x² + 2x - 1
    f(1) # => 4

Placeholders appear in _italics_, with mnemonic names: 𝒆 for expression, 𝒇 for function, 𝒕 for type, and so on.

**Bold face** marks emphasis or conformance requirements.

This specification uses varying levels of formality. Informal descriptions, when used, aim for plain English without sacrificing precision.

Formal definitions of syntax and lexical structure use a Wirth-inspired _extended Backus-Naur Form (EBNF)_, defined by the following grammar:

    Grammar     = Production { Production } .
    Production  = Identifier "=" Expression "." .
    Identifier  = "A" … "Z" { "a" … "z" | "A" … "Z" } .

    Expression  = Alternative { "|" Alternative } .
    Alternative = Term { Term } .

    Term        = Identifier
                | Literal
                | Range
                | Negation
                | Group
                | Option
                | Repetition
                .

    Range       = Literal " … " Literal

    Literal     = '"' Character { Character } '"'
                | "'" Character { Character } "'"
                .

    Hex         = "0" … "9" | "A" … "F" .
    Character   = "U+" Hex Hex [Hex Hex] [Hex Hex] .
    CharClass   = U+00 … U+10FFFF .

    Group       = "(" Expression ")" .
    Option      = "[" Expression "]" .
    Repetition  = "{" Expression "}" .

    Negation    = "~" Group
                | "~" Identifier
                | "~" Literal
                .

A _production_ has a name, an **`=`**, an expression, and a terminating **`.`**. Productions combine identifiers, terminals, and the following operators, in order of increasing precedence:

    |  alternation
    () grouping
    ~  negation
    [] optional   (0 or 1 times)
    {} repetition (0 to n times)

**`|`** separates alternatives and binds least tightly, **`{ … }`** denotes zero or more repetitions of the enclosed expression; **`[ … ]`** denotes zero or one (_i.e._, the expression is optional). Parentheses group. Literal strings appear in double or single quotes; whitespace is significant only inside quotes.

In lexical definitions, two literal characters separated by a horizontal ellipsis **`…`** denotes any single character in the inclusive Unicode range. The same character is used informally elsewhere in the spec to denote enumerations or elided code. **`…`** (`U+2026`) is not a token of the Tungsten language itself.

Non-terminals are CamelCase; abstract terminal symbols are UPPERCASE.

A phrase of the form **`(* … *)`** gives an informal description of the symbol being defined — for example, the notion of a 'control character' could be defined this way.

The notation for lexical and syntactic definitions is nearly identical, but their meanings differ: a _lexical definition_ operates on the individual characters of the input source, while a _syntactic definition_ operates on the stream of tokens produced by lexical analysis. The grammars in the next chapter, _Lexical Analysis_, are lexical definitions; grammars in subsequent chapters are syntactic definitions.

## Conformance

In this specification, **must** indicates a requirement of an implementation or a program; **must not** indicates a prohibition.

Violating a **must** or **must not** requirement results in undefined behavior. Undefined behavior is also signaled by the phrase _undefined behavior_ or by the absence of any explicit definition. There three forms are equivalent; all describe behavior that is undefined.

The word **may** indicates _permission_, never _correctness_.

A _strictly conforming program_ **must** use only the features of the language described in this specification. In particular, it **must not** produce output or exhibit behavior that depends on any unspecified, undefined, or implementation-defined behavior.

A _conforming implementation_ **must** accept every strictly conforming program. It **may** offer extensions, provided they do not alter the behavior of any strictly conforming program.

A _conforming program_ is one that is acceptable to a conforming implementation.

A conforming implementation **must** be accompanied by a document defining all implementation-defined characteristics and all extensions.

This specification contains explanatory material — called _informative_ or _non-normative_ text — that is not strictly required in a formal language specification. Examples illustrate possible forms of the constructions described. References point to related clauses. Notes and Implementer Notes offer guidance to implementers and programmers. Informative appendices provide additional information and summarize material from the body of the specification. All text not marked as informative is _normative_.

Certain features are marked _deprecated_. They are normative in this edition but are not guaranteed to exist in future revisions. Use of deprecated features is strongly discouraged, and a conforming implementation **must** emit warnings when they are used.

## Terms and Definitions

For the purposes of this document, the terms below apply. Additional definitions are introduced using **_bold italic text_**.

argument
: A value passed to a method, intended to map to a corresponding parameter.

behavior
: An observable action or effect.

behavior, implementation-defined
: Behavior that may vary between implementations, but that every conforming implementation must document.

behavior, undefined
: Behavior for which this specification imposes no requirements. Typically the consequence of an erroneous program or data.

behavior, unspecified
: Behavior selected by the implementation, for which this specification provides no requirements and which need not be documented.

block
: A procedure passed to a method call.

char
: A single ascii character, represented by a single byte.

class
: An object which defines the methods of a set of objects called its _instances_.

class variable
: A variable whose value is shared by all instances of a class.

codepoint
: A single Unicode codepoint, represented by one or more bytes.

constant
: A variable defined within a class that is accessible both internally and externally.

error, fatal
: A condition from which the system cannot continue and must terminate.

error, fatal, rescuable
: A fatal error that may be intercepted by a user-defined handler.

error, non-fatal
: An error that does not terminate the system.

global variable
: A variable accessible anywhere in a program.

instance method
: A method that can be called on instances of a class.

instance variable
: A variable accessible by an object's instance methods.

local variable
: A variable accessible only within a particular scope.

parameter
: A variable declared in the parameter list of a method, intended to map to a corresponding argument at a call site.

Tungsten system
: The program that executes a Tungsten program. Referred to as _the system_ throughout this specification.

value
: A primitive unit of data, having a type and, depending on that type, additional content.

Other terms are defined throughout this specification as needed, with the first occurence being typeset in italics, _like this_.

## Appendices

The appendices contain more detailed background information on various topics.

_[Appendix A]_ describes units of measurement that ship with Tungsten.
_[Appendix B]_ discusses languages that inspired Tungsten.

[Library]:  https://docs.tungsten-lang.org/2015.12.1/libray
[Release]:  https://docs.tungsten-lang.org/2015.12.1/release
[Tutorial]: https://docs.tungsten-lang.org/2015.12.1/tutorial

[Appendix A]: appendix_units_of_measurement.md
[Appendix B]: appendix_language_inspiration.md

## Credits

[Python]: https://docs.python.org/3/reference/introduction.html

Tungsten is a ruby-colored, coffee-flavored elixir made of dragon's scalas, effing sharp crystals, fancy pearls, and wise potions.

> Note: © Copyright 2001-2026, Python Software Foundation.
> This page is licensed under the Python Software Foundation License Version 2.
