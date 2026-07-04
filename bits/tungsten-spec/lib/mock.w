# Spec::Mock — test doubles, stubs, and message expectations
# Provides lightweight mocking for isolating units under test.
#
# Usage:
#   user = double("user", name: "Ada", email: "ada@example.com")
#   allow(service).to receive(:fetch).and_return({ok: true})
#   expect(service).to have_received(:fetch).with(42)

in Tungsten:Spec

# Create a test double with optional stubbed methods
-> double(name = "double", **stubs)
  Double.new(name, stubs)

# Stub a method on a real object
-> allow(object)
  StubProxy.new(object)

# Message expectation on a real object
-> have_received(method_name)
  MessageMatcher.new(method_name)


+ Double
  ro :name
  ro :stubs
  ro :received_messages

  -> new(@name, @stubs = {})
    @received_messages = []

  -> method_missing(name, *args)
    @received_messages.push({method: name, args: args})

    if @stubs.has_key?(name)
      @stubs[name]
    else
      <! UnexpectedMessage.new("#{@name} received unexpected message: #{name}")

  -> respond_to?(name)
    @stubs.has_key?(name) || super

  -> inspect
    "#<Double #{@name}>"


+ StubProxy
  ro :object

  -> new(@object)

  -> to(stub_action)
    stub_action.apply(@object)


+ StubAction
  ro :method_name
  rw :return_value
  rw :return_block
  rw :raise_error

  -> new(@method_name)
    @return_value = nil
    @return_block = nil
    @raise_error  = nil
    @call_log     = []

  -> and_return(value)
    @return_value = value
    self

  -> and_raise(error)
    @raise_error = error
    self

  -> and_call_original
    @call_original = true
    self

  -> apply(object)
    action = .
    original = object.method(@method_name) if object.respond_to?(@method_name)

    object.define_singleton_method(@method_name) -> (*args)
      action.record(args)

      if action.raise_error
        <! action.raise_error
      elsif action.return_block
        action.return_block.call(*args)
      elsif action.call_original && original
        original.call(*args)
      else
        action.return_value

  -> record(args)
    @call_log.push(args)

  -> call_count
    @call_log.size

  -> called_with?(*expected_args)
    @call_log.any?(args -> args == expected_args)


# receive(:method) — creates a StubAction for use with allow()
-> receive(method_name)
  StubAction.new(method_name)


+ MessageMatcher
  ro :method_name
  rw :expected_args
  rw :expected_count

  -> new(@method_name)
    @expected_args  = nil
    @expected_count = nil

  -> with(*args)
    @expected_args = args
    self

  -> once   = tap -> @expected_count = 1
  -> twice  = tap -> @expected_count = 2
  -> times(n) = tap -> @expected_count = n

  -> matches?(object)
    messages = object.received_messages.select(m -> m.method == @method_name)

    if @expected_args
      messages = messages.select(m -> m.args == @expected_args)

    if @expected_count
      messages.size == @expected_count
    else
      messages.any?

  -> failure_message(object)
    "expected #{object.inspect} to have received :#{@method_name}"

  -> negated_failure_message(object)
    "expected #{object.inspect} not to have received :#{@method_name}"


+ UnexpectedMessage < StandardError
