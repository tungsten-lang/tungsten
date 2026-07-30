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

# (d) var referenced ONLY inside string interpolation within a fn.
# Regression guard: interpolation parts are packed-body pairs invisible to
# ast_children, so evr_walk must special-case them — a wrongly demoted var
# made this print "value=" compiled.
-> interp_read
  "value=[g_interp]"
gds_check("demote.fn_interp_read", interp_read, "value=44")

# (e) main-only loop accumulator: demotable, must still compute
acc = 0
i = 0
while i < 10
  acc = acc + i
  i += 1
gds_check("demote.main_only_accumulator", acc, "45")

# (f) $-sigil gvar mutated through a helper fn and read back at top level:
# gvars are the explicit global mechanism (lower_gvar_set stores from ANY
# scope), so the demotion skip must never apply to them. A demoted
# $spec_depth-style counter read nil inside the spec DSL ("nil + int").
$gds_counter = 0
-> gds_bump
  $gds_counter = $gds_counter + 1
gds_bump
gds_bump
gds_bump
gds_check("demote.gvar_helper_mutation", $gds_counter, "3")

# (g) var read ONLY inside an ELSIF arm of a fn: elsif_clauses are
# [condition, body] packed pairs invisible to ast_children — the walker
# must descend them or the read sees an unset global (wassat covering's
# WASSAT_COVER_MAX_EDGES regression shape).
g_elsif_only = 77
-> gds_elsif_read(n)
  if n == 1
    1
  elsif n == g_elsif_only - 75
    g_elsif_only
  else
    3
gds_check("demote.elsif_only_read", gds_elsif_read(2), "77")

<< "global demotion scopes: ok"
