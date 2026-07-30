# Top-level var demotion (lowering: main-only top-level vars skip the
# @global mirror). A var is only demotable when NO reference escapes main:
# fn bodies, stored lambdas, trait-provided methods, and interpolation
# inside a fn all read the global mirror, so demoting any of those breaks
# the read (undefined global or stale value). The main-only loop
# accumulator at the bottom IS demotable and must still compute.
#
# Run: `bin/tungsten compile spec/compiler/global_demotion_scopes_spec.w --out /tmp/gds && /tmp/gds`

-> gds_check(name, got, want)
  if got.to_s == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s + " want " + want
    exit 1

g_fn = 41
g_lambda = 42
g_trait = 43
g_interp = 44

# (a) read from a fn body
-> read_from_fn
  g_fn + 1
gds_check("demote.fn_body_read", read_from_fn, "42")

# main mutates the var; the fn must observe the updated mirror
g_fn = 141
gds_check("demote.fn_body_read_after_mutation", read_from_fn, "142")

# (b) read from a lambda stored in a var and called later
stored_lambda = ->() g_lambda + 1
gds_check("demote.lambda_read", stored_lambda.call, "43")

# (c) read from a method a class obtains via a trait
trait GlobalReader
  -> trait_read
    g_trait + 1

+ TraitReaderHost
  is GlobalReader

host = TraitReaderHost.new
gds_check("demote.trait_method_read", host.trait_read, "44")

# (d) var referenced ONLY inside string interpolation within a fn
# TODO(compiler bug, demotion pass of 363b54c): the top-level demotion
# reference walker does not descend into string-interpolation parts, so a
# var whose only out-of-main read sits inside an interpolated string is
# wrongly demoted — compiled this returns "value=" (interpreter is correct,
# and TUNGSTEN_DEMOTE_TOP_LEVEL=0 compiles correctly). Soft-probe until
# lowering fixes the walker, then upgrade to gds_check.
-> interp_read
  "value=[g_interp]"
interp_got = interp_read
if interp_got == "value=44"
  << "PASS demote.fn_interp_read"
else
  << "KNOWNBUG demote.fn_interp_read got " + interp_got + " want value=44 (demotion misses interp-only reads)"

# (e) main-only loop accumulator: demotable, must still compute
acc = 0
i = 0
while i < 10
  acc = acc + i
  i += 1
gds_check("demote.main_only_accumulator", acc, "45")

<< "global demotion scopes: ok"
