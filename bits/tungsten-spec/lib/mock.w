# Spec mocks — v1 explicit test doubles.
#
# The language has no method_missing or define_singleton_method, so
# transparent doubles (`user.name` dispatching to a stub) and `allow(x).to
# receive(:y)` cannot be implemented. This provides an explicit double:
#
#   user = double("user", {name: "Ada", email: "ada@example.com"})
#   user.get(:name)        # => "Ada" (and records the access)
#   user.received?(:name)  # => true

-> double(name, stubs)
  Double.new(name, stubs)

+ Double
  ro :name
  ro :stubs
  ro :received

  -> new(@name, @stubs)
    @received = []

  # Fetch a stubbed value, recording the access.
  -> get(key)
    @received.push(key)
    @stubs[key]

  -> received?(key)
    @received.include?(key)

  -> to_s
    "#<Double [@name]>"
