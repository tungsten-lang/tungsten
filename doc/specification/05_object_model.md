# 5. Object Model

Tungsten is object-oriented: **every value is an object**, and every object has a class that defines its behavior. This chapter describes classes, inheritance, traits, methods, fields, and the relationship between language-level objects and the runtime's `WValue` encoding.

Version: 2026.07.04

## 5.1 Everything is an object

Numbers, strings, booleans, `nil`, arrays, classes, modules, and user instances are all objects. There is no parallel universe of "primitive types" outside the object system: an integer still responds to methods, and `4.class` is a class object.

Objects have:

* an identity (as far as the language exposes it)
* a class
* a method suite (inherited and defined)
* optional mutable or immutable state (fields)

Immediate values (small integers, short strings, singletons, and other tagged forms) may not be heap-allocated, but they still behave as objects of their respective classes.

## 5.2 Classes

### 5.2.1 Defining a class

A class is introduced with `+`:

    + Name
      ...

    + Name < Superclass
      ...

    + Name<T, U> < Super<T>
      ...

The class object is created when the definition is evaluated. The body is processed in class context: method definitions install methods on the class; `is Trait` includes traits; layout and accessor declarations describe instance structure.

### 5.2.2 Inheritance

If a superclass is given, the new class is a subclass of that superclass. Method lookup walks from the receiver's class up the superclass chain. The default root for ordinary user classes is `Object`, which itself inherits from `BlankSlate`.

* `BlankSlate` is an explicit nearly empty root, used to build alternate hierarchies.
* `Object` supplies the common protocol: equality, comparison hooks, reflection, field access, `to_s` / `inspect`, and construction helpers.

A class may reopen an existing name: subsequent `+ Name` bodies merge methods into the existing class (last definition of a given method name wins). The first declaration's superclass wins when the class already exists.

### 5.2.3 Generics

Classes and traits may declare type parameters (`+ Matrix<T>`, `+ Mat<T, M, N>`). Constraints restrict parameters:

    + Matrix<T> < Number
      with T in (
        f16 f32 f64
        i8 i16 i32 i64
        ...
      )

Monomorphization and compile-time checking of these parameters are performed by the compiler for compiled code. Type arguments may be identifiers or integer shape parameters (as with fixed-size matrices).

### 5.2.4 The `Class` object

Classes are instances of `Class` (or behave as such). Reflective operations include:

| Message | Meaning |
|---------|---------|
| `obj.class` | The class of `obj` |
| `obj.class_name` | String name of the class |
| `ClassName.name` | Name of the class |
| `ClassName.superclass` / `ancestors` | Hierarchy navigation (core API) |
| `ClassName.methods` | Defined methods (core API) |

Sending `.class` to a class object yields the class metaclass fixpoint used by the implementation (further `.class` sends remain at the class-of-classes).

## 5.3 Instances and construction

### 5.3.1 Allocation and `new`

Creating an instance typically proceeds as:

1. Allocate an object of the class (fields initially nil / zero as defined by the layout).
2. Invoke initialization — user code usually defines `-> new(...)` which sets fields and may call `super`.
3. Return the instance.

Calling the class as a function, `Dog("Rex", "lab")`, is equivalent to `Dog.new("Rex", "lab")` for ordinary classes.

### 5.3.2 Constructor parameters and fields

Parameters prefixed with `@` assign instance fields of the same name:

    -> new(@name, @sound)

A trailing `ro` or `rw` on the constructor requests generation of accessors:

* `ro` — read-only getter (`obj.name`)
* `rw` — getter and setter (`obj.name`, `obj.name = value`)

Standalone declarations in the class body are also recognized:

    ro :name
    rw :breed

### 5.3.3 `self` inside instance methods

In an instance method, `self` is the receiver. Fields are accessed as `@field` or via accessors. Bare calls resolve against `self` when they name instance methods.

## 5.4 Methods

### 5.4.1 Instance methods

    -> speak
      "woof from [@name]"

    -> distance(other)
      ...

    -> +/1
      ...

Methods are identified by name and, where the implementation supports overloading, by arity and type annotations. The arity suffix form (`-> add/2`) is a definition-site convenience that binds positional arguments without naming them.

### 5.4.2 Class methods

    -> .parse(string)
      ...

A leading `.` installs the method on the class object (callable as `Name.parse(...)`), distinct from instance methods of the same base name.

### 5.4.3 Abstract methods

A method declared with no body is abstract. Concrete subclasses or runtime intrinsics provide the implementation. The numeric tower uses this pattern extensively: operations are declared on abstract bases and implemented on concrete numeric classes.

### 5.4.4 Blocks and higher-order methods

Methods may take an implicit or explicit block. The `Enumerable` trait illustrates the contract: a class that implements `each` with a block gains `map`, `select`, `reduce`, and related methods by trait inclusion.

    trait Enumerable
      -> map/& []
        each -> out.push &(item)

Within a block, `item` (and other names established by the callee) may be bound implicitly; `&(...)` invokes the block being defined in arity/`&` style APIs.

### 5.4.5 Operator methods

Classes overload operators by defining methods named with the operator spelling:

    -> +/1
    -> -/1
    -> */1
    -> //1
    -> %/1
    -> **/1
    -> <=>/1
    -> []/1
    -> []=/2

The `Comparable` trait builds `<`, `<=`, `>`, `>=`, and `==` from `<=>`.

## 5.5 Traits

### 5.5.1 Defining a trait

    trait Printable
      -> to_string
        "[self.label]: [self.value]"

      -> print_self
        << self.to_string()

A trait is a reusable bundle of method definitions. It is not instantiated on its own as an ordinary object hierarchy node in the way a class is; it exists to be included.

### 5.5.2 Including a trait

    + Temperature
      is Printable
      ...

The `is TraitName` form splices the trait's methods into the class. The class's own methods override trait methods of the same name. Multiple `is` lines include multiple traits; later definitions override earlier ones on name collision, subject to body order.

Traits may themselves be generic and constrained with `with T in (...)`.

### 5.5.3 Required interface

A trait may call methods that the including class is expected to provide (for example, `Enumerable` requires `each`; `Printable` in the examples requires `label` and `value`). Failure to provide them results in an undefined-method error at the call site, not necessarily at inclusion time.

## 5.6 Fields and layout

### 5.6.1 Instance fields

Instance state is stored in fields, written `@name` in methods. Fields may be introduced by:

* `@`-parameters on `new` or other methods
* assignment to `@name`
* `ro` / `rw` declarations
* `- data` / `- ivars` layout blocks

### 5.6.2 Layout blocks

A class may declare a structured memory layout:

    + BigInt < Int
      - data
        i32 length
        u32 capacity
        u64[] limbs

Layout declarations guide representation, foreign-function interop, and accessor generation. The set of field type codes (`i32`, `u64[]`, `w64`, `ast`, …) is defined by the implementation and core library.

### 5.6.3 Visibility

Instance fields are accessible inside the class's instance methods. Encapsulation beyond that (private fields, module-private methods) follows the core library and implementation conventions; keywords such as `private` may appear in core sources as organizational markers where supported.

## 5.7 Modules and namespaces

Modules (`module Name`) group definitions. Qualified names use colon separators (`Tungsten:AST:Program`). A file-level `in Tungsten:AST` prefix qualifies subsequent class names automatically.

Namespace lookup for superclasses walks outward from the current `in` prefix so that a short superclass name can resolve to a nested class when one has been declared.

## 5.8 Method lookup and `super`

Given a send `recv.name(args)`:

1. Let _C_ be the class of `recv` (or `recv` itself when sending a class method to a class).
2. Search _C_'s method table for `name` (after trait inclusion has been applied).
3. If not found, repeat for `C.superclass`, and so on.
4. Invoke the found method with `self = recv`.

Inside a method, `super` / `super(...)` starts the search at the superclass of the class that defined the currently executing method (not again at the receiver's class), enabling constructors and overrides to chain.

Singleton methods and `method_missing` hooks, where provided by `BlankSlate` / `Object`, participate in lookup as documented by the core library.

## 5.9 Metaclasses (informative)

Classes are objects, so they have a class as well. The implementation maintains a consistent answer for `SomeClass.class` and for chains such as `4.class.class`. User programs ordinarily interact with this only through class methods (`-> .name`) and reflective APIs.

This specification does not require a full Smalltalk-style parallel metaclass hierarchy to be visible in surface syntax. It **does** require that:

* classes are objects
* class methods are distinct from instance methods
* `.class` / `.class_name` behave as described in _Semantics_

## 5.10 Core hierarchy (summary)

```
BlankSlate
  └── Object
        ├── user classes…
        ├── Array, Hash, String, …
        ├── Error
        │     ├── ArgumentError
        │     ├── RangeError
        │     └── TypeError
        └── Number
              ├── Integer / Int … BigInt
              ├── Decimal … BigDecimal
              ├── Float …
              ├── Vector / Matrix / …
              └── Hypercomplex …
```

Traits such as `Comparable` and `Enumerable` are mixed into classes with `is` and appear in the standard library autoload table (`core/tungsten.w`). A class or trait is not part of the default global namespace until registered for autoload or otherwise loaded.

## 5.11 Runtime representation: WValue

At run time, every dynamic language value is a **WValue**: a single 64-bit word using a NaN-boxing scheme. The encoding is designed so that:

* `nil` and `false` are the only falsey values
* small integers, short strings, decimals, and many domain types fit in the word without a heap allocation
* heap objects are aligned pointers with a low-bit sub-tag

Language-level consequences:

| Concern | WValue role |
|---------|-------------|
| Truthiness | Unsigned compare; only encodings of `nil` and `false` are falsey |
| Small integers | Tagged immediates; overflow → heap `BigInt` |
| Object identity for heap objects | Pointer equality of the tagged heap reference |
| Class of immediates | Derived from the tag / sub-tag, not a pointer in the value |

This chapter does **not** restate the full bit layout. Implementers and contributors **must** consult:

* [WValue overview](../WVALUE.md) — quick reference
* [WValue encoding specification](wvalue_encoding.md) — normative bit patterns

A conforming implementation that uses WValue **must** match those bit patterns. An alternate implementation may use a different encoding only if it preserves the observable object model and truthiness rules in this specification; such an alternative is outside the WValue conformance claim.

## 5.12 Autoload and the core library

The standard library is organized as lazily autoloaded classes and traits. The manifest in `core/tungsten.w` registers names:

    + Tungsten
      auto :Array,      "array"
      auto :Comparable, "traits/comparable"
      ...

Referencing an autoloaded constant loads the corresponding source. New core types are invisible to programs until registered in this table (or loaded by explicit path).

## 5.13 GPU objects and dual compilation (informative)

Functions marked `@gpu fn` are not ordinary CPU methods: they are lowered through a GPU dialect emitter (Metal Shading Language in the current primary path). Values and types used in GPU kernels must be representable in that dialect. This does not change the CPU object model; it is a separate compilation path for annotated functions.

## 5.14 Cross-references

* Surface syntax for classes, traits, and methods — _Grammar_
* Dispatch order, truthiness, construction evaluation — _Semantics_
* Lexical form of identifiers and keywords — _Lexical Analysis_
* Standard library catalog — [The Tungsten Core](../CORE.md)
* WValue bit layouts — [wvalue_encoding.md](wvalue_encoding.md), [WVALUE.md](../WVALUE.md)
