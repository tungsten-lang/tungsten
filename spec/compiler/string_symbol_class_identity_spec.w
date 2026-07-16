use core/string_native

+ AtomicIdentityFacade
  -> identity_facade_probe 1

+ ThreadIdentityFacade
  -> identity_facade_probe 129

+ ChannelIdentityFacade
  -> identity_facade_probe 132

+ ArrayIdentityFacade
  -> identity_facade_probe 10

-> fail(name, got, expected)
  << "FAIL class identity [name] got=[got] expected=[expected]"
  exit(1)

-> check(name, got, expected)
  if got != expected
    fail(name, got, expected)

-> check_string_symbol_identity
  # The explicit source import registers String's shared 0xF9 method class
  # before either query. Symbol must nevertheless retain its own identity.
  check("String registration", "".empty?, true)

  symbol = :identity
  check("Symbol type", type(symbol), "Symbol")
  check("Symbol class_name", symbol.class_name, "Symbol")
  symbol_class = symbol.class
  check("Symbol class name", ccall("w_class_identity_class_label", symbol_class), "Symbol")
  check("Symbol class stable bits", wvalue_bits(symbol.class), wvalue_bits(symbol_class))
  check("Symbol is_a name", symbol.is_a?("Symbol"), true)
  check("Symbol is_a class", symbol.is_a?(symbol_class), true)
  check("Symbol not String", symbol.is_a?("String"), false)

  string = "identity"
  check("String type", type(string), "String")
  check("String class_name", string.class_name, "String")
  string_class = string.class
  check("String class name", ccall("w_class_identity_class_label", string_class), "String")
  check("String class stable bits", wvalue_bits(string.class), wvalue_bits(string_class))
  check("String is_a name", string.is_a?("String"), true)
  check("String is_a class", string.is_a?(string_class), true)
  check("String not Symbol", string.is_a?("Symbol"), false)
  check("String/Symbol classes distinct", string_class == symbol_class, false)
  check("Symbol stable after String query", wvalue_bits(symbol.class), wvalue_bits(symbol_class))

-> check_unknown_handle(name, value, key, facade)
  check("[name] type before", type(value), "Unknown")
  check("[name] class_name before", value.class_name, "Unknown")
  before = value.class
  check("[name] class before", before, nil)
  check("[name] class stable before", value.class, before)

  ccall("w_class_identity_register_facade", key, facade)

  check("[name] type after", type(value), "Unknown")
  check("[name] class_name after", value.class_name, "Unknown")
  after = value.class
  check("[name] class after", after, nil)
  check("[name] class stable across facade", after, before)
  check("[name] class stable after", value.class, before)
  check("[name] not facade identity", value.is_a?(facade), false)
  check("[name] facade method dispatch", value.identity_facade_probe, key)

-> check_atomic_identity
  check_unknown_handle("Atomic", Atomic.new(0), 0x01, AtomicIdentityFacade)

-> check_channel_identity
  check_unknown_handle("Channel", Channel.new(1), 0x84, ChannelIdentityFacade)

-> check_thread_identity
  thread = Thread.new ->
    1
  ccall("w_thread_join", thread)
  check_unknown_handle("Thread", thread, 0x81, ThreadIdentityFacade)

-> check_declared_unknown_identity
  atomic = Atomic.new(0)
  check("Declared Unknown class before declaration", atomic.class, nil)
  declared = ccall("w_class_identity_declare_unknown")
  check("Declared Unknown class selected", atomic.class, declared)
  check("Declared Unknown class name", ccall("w_class_identity_class_label", atomic.class), "Unknown")
  ccall("w_class_identity_register_facade", 0x01, AtomicIdentityFacade)
  check("Declared Unknown class after facade", atomic.class, declared)
  check("Declared Unknown public class_name", atomic.class_name, "Unknown")
  check("Declared Unknown facade dispatch", atomic.identity_facade_probe, 1)

-> check_array_alias_identity
  # Array, ByteArray, BoolArray, and TypedArray deliberately share dispatch
  # key 0x0A. Registering a source facade may change method dispatch, but must
  # not publish that facade as Array's public class.
  value = argv()
  before = value.class
  check("Array alias class before", ccall("w_class_identity_class_label", before), "Array")
  ccall("w_class_identity_register_facade", 0x0A, ArrayIdentityFacade)
  check("Array alias class stable bits", wvalue_bits(value.class), wvalue_bits(before))
  check("Array alias class_name", value.class_name, "Array")
  check("Array alias not facade identity", value.is_a?(ArrayIdentityFacade), false)
  check("Array alias facade method dispatch", value.identity_facade_probe, 10)

-> check_array_alias_cold_identity
  # Registration happens before the first public class query in this mode.
  # The 0x0A method facade must not become Array's public identity even on a
  # cold cache miss; __w_type remains the authority for the public name.
  value = argv()
  ccall("w_class_identity_register_facade", 0x0A, ArrayIdentityFacade)
  selected = value.class
  check("Array cold alias class", ccall("w_class_identity_class_label", selected), "Array")
  check("Array cold alias class stable", wvalue_bits(value.class), wvalue_bits(selected))
  check("Array cold alias class_name", value.class_name, "Array")
  check("Array cold alias not facade identity", value.is_a?(ArrayIdentityFacade), false)
  check("Array cold alias facade method dispatch", value.identity_facade_probe, 10)

-> check_late_matching_hash_identity
  # The first query caches the thin program's current Hash class (normally a
  # generated stub). A later matching registration must replace that result.
  value = ccall("w_class_identity_native_hash")
  before = value.class
  check("Late Hash initial class", ccall("w_class_identity_class_label", before), "Hash")
  declared = ccall("w_class_identity_declare_hash")
  check("Late Hash declared class", ccall("w_class_identity_class_label", declared), "Hash")
  after = value.class
  check("Late Hash cache replaced", before == after, false)
  check("Late Hash registered class selected", wvalue_bits(after), wvalue_bits(declared))
  check("Late Hash class stable", wvalue_bits(value.class), wvalue_bits(declared))
  check("Late Hash class_name", value.class_name, "Hash")

# Class definitions are hoisted ahead of top-level expressions. The delayed
# benchmark-only registration bridge therefore makes same-process before/after
# assertions possible without changing production registration order.
args = argv()
only = args.size() == 0 ? "all" : args[0]
if only in ("all" "symbol")
  check_string_symbol_identity()
if only in ("all" "atomic")
  check_atomic_identity()
if only in ("all" "channel")
  check_channel_identity()
if only in ("all" "thread")
  check_thread_identity()
if only == "declared"
  check_declared_unknown_identity()
if only in ("all" "alias_cold")
  check_array_alias_cold_identity()
if only in ("all" "alias")
  check_array_alias_identity()
if only in ("all" "late_hash")
  check_late_matching_hash_identity()

<< "PASS public class identity [only]: __w_type-authoritative identity, alias invalidation, and late matching registration"
