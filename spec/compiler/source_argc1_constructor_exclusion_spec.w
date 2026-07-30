+ PositiveTarget
  -> argc1(value)
    value

+ PositiveHolder
  -> new
    @receiver = PositiveTarget.new()

  -> call(value)
    @receiver.argc1(value)

+ Atomic
  -> argc1(value)
    value

+ AtomicHolder
  -> new
    @receiver = Atomic.new(0)

  -> call(value)
    @receiver.argc1(value)

+ Channel
  -> argc1(value)
    value

+ ChannelHolder
  -> new
    @receiver = Channel.new(1)

  -> call(value)
    @receiver.argc1(value)

+ Thread
  -> argc1(value)
    value

+ ThreadHolder
  -> new
    @receiver = Thread.new ->
      1

  -> call(value)
    @receiver.argc1(value)

+ Response
  -> argc1(value)
    value

+ ResponseHolder
  -> new
    @receiver = Response.new(200, "ok")

  -> call(value)
    @receiver.argc1(value)

+ BigArray
  -> argc1(value)
    value

+ BigArrayHolder
  -> new
    @receiver = BigArray.new(:w64, 4)

  -> call(value)
    @receiver.argc1(value)

+ SmallArray
  -> argc1(value)
    value

+ SmallArrayHolder
  -> new
    @receiver = SmallArray.new(:w64, 4)

  -> call(value)
    @receiver.argc1(value)

+ ByteArray
  -> argc1(value)
    value

+ ByteArrayHolder
  -> new
    @receiver = ByteArray.new(4)

  -> call(value)
    @receiver.argc1(value)

+ BoolArray
  -> argc1(value)
    value

+ BoolArrayHolder
  -> new
    @receiver = BoolArray.new(4)

  -> call(value)
    @receiver.argc1(value)

-> excl_check(name, got, expected)
  if got != expected
    << "FAIL " + name + ": got=" + got.to_s() + " expected=" + expected.to_s()
    exit(1)
  << "PASS " + name

# Holders whose reopened receiver classes dispatch argc1 on both engines.
# (Response/BigArray/SmallArray holders stay definition-only: the
# interpreter's `+ Name` shadows those builtin constructors, and the
# compiled runtime does not attach source methods to Response instances.)
positive = PositiveHolder.new()
excl_check("positive holder", positive.call(11), 11)
atomic = AtomicHolder.new()
excl_check("atomic holder", atomic.call(12), 12)
channel = ChannelHolder.new()
excl_check("channel holder", channel.call(13), 13)
thread = ThreadHolder.new()
excl_check("thread holder", thread.call(14), 14)
bytes_holder = ByteArrayHolder.new()
excl_check("byte array holder ctor", bytes_holder != nil, true)
bools_holder = BoolArrayHolder.new()
excl_check("bool array holder ctor", bools_holder != nil, true)

# The excluded constructors must still run the BUILTIN init: a boxed-length
# marshalling truncation would silently hand back zero-length arrays.
byte_arr = ByteArray.new(4)
excl_check("byte array size", byte_arr.size, 4)
byte_arr[3] = 7
excl_check("byte array store", byte_arr[3], 7)
# BoolArray.new(n) is documented capacity-n/size-0 (w_bool_array_new): the
# length argument must still survive as capacity — filling to 4 works and
# the values round-trip.
bool_arr = BoolArray.new(4)
excl_check("bool array new size", bool_arr.size, 0)
bool_arr.push(true)
bool_arr.push(false)
bool_arr.push(true)
bool_arr.push(true)
excl_check("bool array filled size", bool_arr.size, 4)
excl_check("bool array roundtrip 0", bool_arr[0], true)
excl_check("bool array roundtrip 1", bool_arr[1], false)
excl_check("bool array roundtrip 3", bool_arr[3], true)

<< "PASS source argc1 constructor exclusion"
