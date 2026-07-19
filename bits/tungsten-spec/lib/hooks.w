# Spec hooks — before/after each/all.
# Hooks register into global stacks; describe/context snapshot the stack
# depth on entry and truncate back on exit, so a hook only applies inside
# the group where it was declared (and its nested groups).
#
# Block capture is engine-split: compiled code binds the named `&block`
# param to a real closure (storable directly); the interpreter leaves the
# named param nil but still lets `&()` yield, so it stores a wrapper
# lambda (`h = -> () &()`) instead. Both branches verified by probe.
#
# CALL-SITE GOTCHA: `before_each ->` (paren-less, zero-arg) parses as the
# implicit-.each iteration syntax (`expr -> block` == expr.each), so these
# must be called with explicit parens: `before_each() -> ...`.
#
# LIMITATION: a raise from inside a hook unwinds across the stored-wrapper
# `.call` boundary, which segfaults the interpreter today — hooks must not
# raise (expectations inside hooks are fine: they flag, not raise).

$spec_before_each = []
$spec_after_each = []
$spec_after_all_pending = []

-> before_each(&block)
  if block != nil
    $spec_before_each.push(block)
    return nil
  h = -> () &()
  $spec_before_each.push(h)
  nil

-> after_each(&block)
  if block != nil
    $spec_after_each.push(block)
    return nil
  h = -> () &()
  $spec_after_each.push(h)
  nil

-> before(&block)
  if block != nil
    $spec_before_each.push(block)
    return nil
  h = -> () &()
  $spec_before_each.push(h)
  nil

-> after(&block)
  if block != nil
    $spec_after_each.push(block)
    return nil
  h = -> () &()
  $spec_after_each.push(h)
  nil

# Examples run immediately, so a before_all block declared at the top of a
# group is equivalent to running it right now.
-> before_all(&)
  &()
  nil

# after_all blocks run when the enclosing describe/context exits.
-> after_all(&block)
  if block != nil
    $spec_after_all_pending.push(block)
    return nil
  h = -> () &()
  $spec_after_all_pending.push(h)
  nil

-> spec_run_hooks(hooks)
  hooks.each -> (h)
    h.call
  nil

# Drop hook registrations back to a snapshot size (group exit).
-> spec_truncate(arr, n)
  while arr.size > n
    arr.pop()
  nil

# Unwind a describe/context group: run after_all hooks registered inside
# it, truncate the hook stacks to their entry snapshots, drop the depth.
-> spec_unwind_group(nb, na, nz)
  while $spec_after_all_pending.size > nz
    h = $spec_after_all_pending.pop()
    h.call
  spec_truncate($spec_before_each, nb)
  spec_truncate($spec_after_each, na)
  spec_depth_down
  nil
