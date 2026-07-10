# 3. Grammar

This chapter defines the syntactic structure of Tungsten programs. It operates on the stream of tokens produced by lexical analysis (see _Lexical Analysis_). Whitespace is generally insignificant at this level except where the lexer has already encoded layout as `INDENT`, `DEDENT`, `NL`, and `SP` tokens.

Syntax is specified with the same Wirth-inspired EBNF used in earlier chapters, together with informal English. Non-terminals are CamelCase; terminals appear as quoted keywords or as token names from the lexer (`ID`, `INDENT`, `NL`, and so on).

Version: 2026.07.04

## 3.1 Programs and modules

A Tungsten _program_ is a sequence of top-level forms. There is no required `main` declaration: a program file is evaluated top to bottom (see _Semantics_).

    Program     = { TopLevel } EOF .
    TopLevel    = UseDirective
                | NamespaceDecl
                | ClassDef
                | TraitDef
                | ModuleDef
                | MethodDef
                | FnDef
                | GpuKernelDef
                | Expression
                | NL
                .

Top-level expressions and method definitions are ordinary statements of the file's global scope.

### 3.1.1 Use directives

    UseDirective = "use" UsePath NL .
    UsePath      = (* path string or bare identifier path, as scanned by the lexer *) .

A `use` directive loads another Tungsten source unit into the current program. The path names a library or relative module; resolving it is implementation-defined (see the Bit package layout and the load path).

Examples:

    use cache
    use tungsten/json

Some programs also write `use name as alias` or `from path use (names)`. Where present, these are extensions of the same import idea; a conforming program **must** only use forms accepted by the implementation it targets.

### 3.1.2 Namespace declaration

    NamespaceDecl = "in" QualifiedName NL .
    QualifiedName = Identifier { ":" Identifier } .

A file-level `in Namespace` prefix rewrites subsequent bare class names so that `+ Foo` becomes `Namespace:Foo`. Nested namespaces use colon-separated segments (`Tungsten:AST`).

### 3.1.3 Module definition

    ModuleDef = "module" Identifier [ NL INDENT { TopLevel } DEDENT ] .

Modules group related definitions under a name. Class and method forms inside a module body are defined in that module's scope.

## 3.2 Significant indentation

Tungsten closes blocks by dedent. There are no `end` keywords and no mandatory braces around compound statements.

Rules:

1. Indentation **must** be exactly two spaces per level (see _Lexical Analysis_ §2.4).
2. A compound form that takes a body expects `NL`, then `INDENT`, a non-empty sequence of statements, then `DEDENT`.
3. Blank lines and comments do not affect the indent stack.
4. Implicit line joining inside `()`, `[]`, `{}`, and related delimiters suppresses `NL` between physical lines; indentation on those continuation lines is insignificant.

Informally, a _block_ is:

    Block = NL INDENT { Statement } DEDENT .

Many constructs also allow a single trailing expression on the same line as the introducer (inline form).

## 3.3 Classes

    ClassDef = "+" ClassName [ TypeParams ] [ Role ]
               [ "<" SuperName [ TypeParams ] [ Role ] ]
               [ Block ]
             .

    ClassName  = QualifiedName .
    SuperName  = QualifiedName .
    TypeParams = "<" TypeArg { "," TypeArg } ">" .
    TypeArg    = Identifier | IntegerLiteral .
    Role       = "[" Identifier "]" .

The token that begins a class definition is the class-introducer `+` (lexed as a dedicated class-definition token when used in this position).

Examples:

    + Dog
      -> new(@name, @breed) rw
      -> speak
        "woof from [@name]"

    + Puppy < Dog
      -> speak
        "yip from [@name]"

    + Matrix<T> < Number
      with T in (f32 f64 i64)
      ...

### 3.3.1 Class body

A class body may contain:

| Form | Meaning |
|------|---------|
| Method definitions (`->`) | Instance or class methods |
| `is TraitName` | Trait inclusion |
| `ro :field` / `rw :field` | Standalone accessor declarations |
| `with T in (…)` | Generic type-parameter constraints |
| `- data` / `- ivars` | Memory layout declarations |
| Nested expressions | Evaluated when the class is defined, as permitted by the implementation |

### 3.3.2 Construction

Instances are created with the class method `new`, or by calling the class as a function:

    d = Dog.new("Rex", "lab")
    d = Dog("Rex", "lab")

Both forms invoke the class's constructor protocol (see _Object Model_).

## 3.4 Traits

    TraitDef     = "trait" Identifier [ TypeParams ] [ Block ] .
    TraitInclude = "is" QualifiedName [ TypeParams ] NL .

A trait packages methods for reuse. A class (or another definition site that accepts the form) includes a trait with `is`:

    trait Printable
      -> to_string
        "[self.label]: [self.value]"

    + Temperature
      is Printable
      -> new(@value, @scale)
      -> label
        "Temperature"

Including a trait splices the trait's method definitions into the class. Methods defined on the class itself take precedence over methods of the same name from the trait (last definition wins when the class body is processed).

Generic traits may carry type parameters and `with T in (…)` constraints, matching the class form.

## 3.5 Methods and functions

### 3.5.1 Method definitions

    MethodDef = "->" [ "." ] MethodName [ Arity | ParamList ]
                [ ParamTypes ] [ ReturnType ]
                MethodBody
              .

    MethodName  = Identifier | OperatorName .
    Arity       = "/" ( Digit { Digit } | "*" | "&" ) .
    ParamList   = "(" [ Param { "," Param } ] ")" .
    Param       = [ "@" ] Identifier [ ":" TypeName ] [ "=" Expression ]
                | "*" Identifier
                | "&" [ Identifier ]
                .
    ParamTypes  = "(" TypeName { TypeName } ")" .
    ReturnType  = TypeName .
    MethodBody  = Block
                | InlineBody
                | (* empty — abstract / interface method *)
                .
    InlineBody  = [ ":" | "=" ] Expression
                | Expression
                .

A leading `.` after `->` marks a _class method_ (defined on the class object rather than on instances):

    -> .initialize
    -> .parse(string)

### 3.5.2 Parameters and arity shorthand

Named parameters appear in parentheses. A parameter prefixed with `@` binds the argument to an instance field of the same name (common on constructors):

    -> new(@name, @breed) rw

The optional trailing `ro` or `rw` on a constructor generates read-only or read-write accessors for those fields.

Arity shorthand omits the parameter list and binds positional arguments as `@1`, `@2`, … (or as internal positional formals of the same meaning):

    -> add/2
      @1 + @2

    -> ==/1
      ...

`/*` denotes a splat; `/&` denotes a block-only method.

A method name may end with `=` for a setter (`-> name=(value)`).

A method with **no body** is abstract: concrete subclasses or the runtime **must** supply an implementation before the method is successfully invoked.

### 3.5.3 Pure functions

    FnDef = "fn" Identifier [ ParamList ] [ ParamTypes ] [ ReturnType ] MethodBody .

A `fn` definition is a pure, auto-memoized function. Aside from purity and memoization, its surface form resembles a method without a receiver.

### 3.5.4 Lambdas and blocks

    Lambda = "->" [ ParamList | Arity ] ( Block | "{" { Statement } "}" | Expression ) .

Blocks passed to methods may be written as multiline `->` forms or as brace blocks:

    [1, 2, 3].each ->(x)
      << x * 2

    [1, 2, 3].each ->(x) { << x }

A block may bind parameters explicitly, or rely on an implicit `item` (and related block bindings) supplied by the callee, as with many `Enumerable` methods.

An expression followed by `->` on the same line is treated as an implicit `each` when the grammar permits:

    (1..10) ->(i)
      << i

### 3.5.5 GPU kernels

    GpuKernelDef = "@gpu" "fn" Identifier ParamList MethodBody .

Functions annotated `@gpu fn` are compiled through the Metal (or other GPU) dialect path rather than ordinary method lowering. Their bodies are restricted to constructs the GPU emitter supports.

## 3.6 Statements and control flow

    Statement = Expression NL
              | ControlForm
              | MethodDef
              | ...
              .

### 3.6.1 Conditional forms

    If = "if" Expression Block
         { "elsif" Expression Block }
         [ "else" Block ]
       | "if" Expression "then" Expression [ "else" Expression ]
       .

    Unless = "unless" Expression Block [ "else" Block ] .

Suffix conditionals attach to a simple expression on the same line:

    Expression "if" Expression
    Expression "unless" Expression

### 3.6.2 Loops

    While = "while" Expression Block .
    Until = "until" Expression Block .
    Loop  = "loop" Block .

Suffix forms:

    Expression "while" Expression

`with` iterates one or more bindings:

    With = "with" Binding { "," Binding } Block .
    Binding = Identifier "in" Expression .

    parallel "with" Identifier "in" Expression Block

`break`, `next` / `continue`, `redo`, and related loop keywords have their usual control-transfer meanings (see _Semantics_).

### 3.6.3 Case

    Case = "case" [ Expression ] CaseBody .

Case bodies use `when` clauses and an optional `else`, or arrow-style pattern arms:

    case value
      when 1
        << "one"
      when 2, 3
        << "two or three"
      else
        << "other"

    case
      when y > 10
        << "big"
      when y > 5
        << "medium"
      else
        << "small"

A value-bearing `case` compares the subject against `when` patterns (desugared to equality or pattern match). A condition-only `case` evaluates guards in order.

### 3.6.4 Exceptions

    Begin = "begin" Block
            [ "rescue" [ Identifier [ ":" ClassName ] ] Block ]
            [ "ensure" Block ]
          .

    Raise = "raise" [ Expression ] .

Suffix rescue:

    Expression "rescue" Expression

### 3.6.5 Return, yield, super

    Return = "return" [ Expression ] .
    Yield  = "yield" [ ArgList ] .
    Super  = "super" [ ArgList ] .

`super` invokes the method of the same name on the superclass (or the next method in the lookup chain). `yield` transfers control into the block associated with the current call.

## 3.7 Expressions

Expressions form a precedence hierarchy. From lowest binding power to highest (summary):

| Level | Operators / forms |
|-------|-------------------|
| Assignment | `=`, compound assigns (`+=`, `-=`, …), multi-assign |
| Ternary | `cond ? a : b` and related conditional expressions |
| Message chain / call | `.name`, bare calls, blocks |
| Range | `..`, `...` |
| Pipeline | `/` as pipeline (where applicable), chained continuation |
| Boolean or | `or`, `\|\|` (implementation-dependent spellings) |
| Boolean and | `and`, `&&` |
| Membership | `in` |
| Comparison | `<`, `<=`, `>`, `>=`, `<=>` |
| Equality | `==`, `!=`, `=~` |
| Bitwise or / xor / and | `\|`, `^`, `&` (and dotted forms) |
| Shift | `<<`, `>>` |
| Add / subtract | `+`, `-` (and elementwise `.+`, `.-`) |
| Multiply / divide / remainder | `*`, `/`, `%`, `·`, and related product operators |
| Power | `**`, superscript exponents (`x⁷`) |
| Unary | `!`, `-`, `√`, … |
| Primary | literals, `self`, `super`, groups, collections, calls |

Infix operators **must** be surrounded by whitespace (see _Lexical Analysis_ §2.3). Juxtaposition without spaces is reserved for quantity and unit forms (`10m/s`).

### 3.7.1 Assignment

    Assign = LValue "=" Expression .
    LValue = Identifier
           | "@" Identifier
           | CallOrIndex
           | MultiTarget
           .

Compound assignment (`+=`, `-=`, `*=`, `/=`, `%=`, `<<=`, `>>=`, and similar forms recognized by the implementation) desugars to a binary operation followed by assignment.

### 3.7.2 Calls and message sends

    Call = [ Receiver "." ] MethodName [ ArgList ] [ BlockArg ]
         | Receiver ArgList
         .

    ArgList  = "(" [ Expression { "," Expression } ] ")"
             | BareArgs
             .
    BlockArg = Lambda | BraceBlock .

A receiver may be omitted for bare calls in the current scope. Safe navigation and continuation lines that begin with `.` chain additional messages onto the preceding expression (explicit line joining, _Lexical Analysis_ §2.2.3).

### 3.7.3 Primary expressions

    Primary = Literal
            | Identifier
            | "self"
            | "true" | "false" | "nil"
            | "(" Expression ")"
            | ArrayLiteral
            | HashLiteral
            | Lambda
            | InterpolationString
            | ...
            .

Instance variables are written `@name`. Positional method arguments in arity form are `@1`, `@2`, …. Class variables and other sigils follow the implementation's established conventions where documented.

## 3.8 Literals (overview)

Literal forms are defined primarily in _Lexical Analysis_. For the purposes of the grammar, a _literal_ is any token or token sequence that denotes a constant value without evaluation of subexpressions (except string interpolation).

| Kind | Examples | Notes |
|------|----------|-------|
| Integer | `42`, `0xFF`, `0b1010`, `0o77` | Optional base prefixes; underscores allowed |
| Decimal | `3.14`, `0.1` | Bare fractions are exact decimals |
| Float | `~3.14` | Machine floats are opt-in with `~` |
| String | `"hello"`, `"hi [name]"` | Interpolation via `[Expression]` |
| Symbol | `:name` | |
| Boolean | `true`, `false` | |
| Nil | `nil` | |
| Array | `[1, 2, 3]` | |
| Hash | `{name: "Alice", age: 30}` | |
| Range | `1..10`, `1...10` | Inclusive / exclusive |
| Byte array | `« ff 00 a5 »` | Hex bytes |
| Currency | `$3.50`, `25¢` | |
| Quantity / units | `5 kg`, `100 mph` | See units appendix |
| Date / time | `2024-01-15`, `14:30:00` | |
| Duration | `5m30s` | |
| Character / codepoint | `U+0041`, `:-A` | |
| Regex | implementation-defined delimiters | |

String interpolation embeds a full expression:

    StringInterp = "[" Expression "]" .

## 3.9 Operators as syntactic sugar

Most operators are method sends on the left operand. Writing `a + b` is equivalent in meaning to sending the method `+` to `a` with argument `b`, for types that overload operators. The parser may lower some operators to dedicated AST nodes for built-in types; the semantic model remains message-based (see _Semantics_ and _Object Model_).

Notable special cases:

* `<=>` is always a method call (`left.<=>(right)`).
* Superscript digits after an expression desugar to exponentiation (`x⁷` ⇒ `x ** 7`).
* `√expr` desugars to a unary square-root send.
* Print forms: `<< expr` prints values; `<- expr` is the related print variant accepted by the parser.

## 3.10 Layout and data declarations

Inside a class body, a typed memory layout may be introduced with `- data` or `- ivars`:

    - data
      i32 length
      u32 capacity
      u64[] limbs

    - ivars
      @field1 w64
      @field2 ast

These declarations describe instance storage for the class. Field names, types, and accessor generation interact with `ro` / `rw` and constructor `@`-parameters (see _Object Model_). The precise set of type tokens accepted in a layout block is implementation-defined but **must** be documented by the implementation.

## 3.11 Grammar notes

1. The grammar is indentation-sensitive. Implementations **must** use the `INDENT` / `DEDENT` stream from the lexer rather than re-deriving layout in the parser.
2. Longest-match at the lexical level means the parser never re-splits tokens.
3. Operator methods may use operator spellings as method names (`-> +/1`, `-> []/1`, `-> []=/2`).
4. Forms marked reserved in _Lexical Analysis_ **must not** appear as identifiers in a strictly conforming program, even if a particular implementation temporarily accepts them.
5. This chapter describes the surface language used by the self-hosted compiler and the documented examples. Where an older or alternate host accepts a superset or subset, the self-hosted compiler is the reference for conformance of the language as of this version.

## 3.12 Cross-references

* Token definitions — _Lexical Analysis_
* Evaluation, scoping, and control-flow meaning — _Semantics_
* Classes, traits, fields, and dispatch — _Object Model_
* Floating-point modes that affect expressions — _Floating-Point Math Modes_
* Runtime value encoding — [WValue encoding](wvalue_encoding.md), [WValue overview](../WVALUE.md)
