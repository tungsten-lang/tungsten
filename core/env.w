# Env — the current process environment.
#
# Names and values are Strings. `to_h`, `keys`, and `each` operate on a
# point-in-time snapshot; concurrent external libc mutation is outside the
# language contract. Runtime-mediated access remains subject to the sandbox.
+ Env
  -> .get(name, default = nil)
    value = env(name)
    value == nil ? default : value

  -> .[](name)
    get(name)

  -> .fetch(name, default = ENV_FETCH_MISSING, &)
    value = env(name)
    if value != nil
      return value
    if block?
      return yield name
    if default != ENV_FETCH_MISSING
      return default
    raise "key not found: " + name

  -> .set(name, value)
    ccall("w_setenv", name, value)

  -> .[]=(name, value)
    set(name, value)

  -> .delete(name)
    ccall("w_unsetenv", name)

  -> .key?(name)
    env(name) != nil

  -> .include?(name)
    key?(name)

  -> .keys
    ccall("w_env_keys")

  -> .values
    to_h().values()

  -> .to_h
    ccall("w_env_to_h")

  -> .size
    keys().size()

  -> .empty?
    size() == 0

  -> .each(&)
    snapshot = to_h()
    snapshot.each -> (name, value)
      yield name, value
    self

# Identity-bearing default token for Env.fetch. It stays out of the autoload
# manifest and is declared after Env so generated Core documentation identifies
# this file by its public facade.
+ EnvFetchMissing

ENV_FETCH_MISSING = EnvFetchMissing.new
