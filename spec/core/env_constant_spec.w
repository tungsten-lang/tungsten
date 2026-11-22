# `ENV["X"]` resolves to the Env facade from any scope. Inside a method it was
# treated as a call of an abstract `ENV` method on self.

Env.set("TUNGSTEN_ENV_SPEC", "yes")

+ EnvReader
  -> read
    ENV["TUNGSTEN_ENV_SPEC"]
  -> .read_class
    ENV.fetch("TUNGSTEN_ENV_SPEC", "missing")

-> read_fn
  ENV["TUNGSTEN_ENV_SPEC"]

fails = 0
if ENV["TUNGSTEN_ENV_SPEC"] != "yes"
  << "FAIL top level"
  fails += 1
if EnvReader.new.read != "yes"
  << "FAIL instance method"
  fails += 1
if EnvReader.read_class != "yes"
  << "FAIL class method"
  fails += 1
if read_fn() != "yes"
  << "FAIL fn"
  fails += 1
if ENV.key?("TUNGSTEN_ENV_SPEC_ABSENT")
  << "FAIL key?"
  fails += 1
exit(1) if fails > 0
<< "PASS env constant"
