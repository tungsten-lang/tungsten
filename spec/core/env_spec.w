use core/env

-> check(name, condition)
  if condition
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

name = "TUNGSTEN_CORE_ENV_SPEC"
old = Env.get(name)

begin
  Env.delete(name)
  check("env.get.missing", Env.get(name) == nil)
  check("env.get.default", Env.get(name, "fallback") == "fallback")
  check("env.fetch.default", Env.fetch(name, "fallback") == "fallback")
  check("env.fetch.empty_hash_default", Env.fetch(name, {}) == {})
  fetched = Env.fetch(name) -> (missing)
    "missing:" + missing
  check("env.fetch.block", fetched == "missing:" + name)

  missing_raises = false
  begin
    Env.fetch(name)
  rescue error
    missing_raises = true
  check("env.fetch.missing", missing_raises)

  check("env.set", Env.set(name, "one") == "one")
  check("env.get", Env.get(name) == "one")
  check("env.index", Env[name] == "one")
  Env[name] = "two"
  check("env.index_set", Env.get(name) == "two")
  check("env.membership", Env.key?(name) && Env.include?(name))
  check("env.keys", Env.keys().include?(name))
  check("env.values", Env.values().include?("two"))

  snapshot = Env.to_h()
  check("env.to_h", snapshot[name] == "two" && snapshot.size() == Env.size())

  seen = nil
  returned = Env.each -> (key, value)
    if key == name
      seen = value
  check("env.each", seen == "two" && returned == Env)

  check("env.delete", Env.delete(name) == "two" && !Env.key?(name))
  check("env.delete.missing", Env.delete(name) == nil)

  bad_name = false
  begin
    Env.set("", "value")
  rescue error
    bad_name = true
  check("env.reject.name", bad_name)

  bad_nul_name = false
  begin
    Env.set("BAD\0NAME", "value")
  rescue error
    bad_nul_name = true
  check("env.reject.nul_name", bad_nul_name)

  bad_value = false
  begin
    Env.set(name, 1)
  rescue error
    bad_value = true
  check("env.reject.value", bad_value)

  bad_nul_value = false
  begin
    Env.set(name, "BAD\0VALUE")
  rescue error
    bad_nul_value = true
  check("env.reject.nul_value", bad_nul_value)
ensure
  if old == nil
    Env.delete(name)
  else
    Env.set(name, old)

<< "ALL PASS env_spec"
