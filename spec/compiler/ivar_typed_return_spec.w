# Regression: an annotated machine-i64 instance-method result crossing the
# runtime-dispatch boundary must be boxed.  Returning raw `1` verbatim makes
# the runtime interpret the bits as the false WValue tag.  Ivar-backed getters
# are the small, common trigger exercised here.
#
# Run: `bin/tungsten -o /tmp/ivar-typed-return \
#   spec/compiler/ivar_typed_return_spec.w && /tmp/ivar-typed-return`.

-> helper_one() i64
  1

-> helper_large() i64
  1073741824

+ TypedReturnField
  -> new
    @one = helper_one()
    @large = helper_large()

  -> one() i64
    @one

  -> large() i64
    @large

probe = TypedReturnField.new()
if probe.one() != 1
  << "FAIL ivar typed return one got=" + probe.one().to_s()
  exit(1)
if probe.large() != 1073741824
  << "FAIL ivar typed return large got=" + probe.large().to_s()
  exit(1)
<< "PASS ivar typed return boxing"
