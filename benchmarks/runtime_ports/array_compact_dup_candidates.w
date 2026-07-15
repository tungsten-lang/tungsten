# Benchmark-only source candidates for Array#compact and Array#dup. The public
# methods and their runtime IC registrations remain untouched until each
# method independently clears the unique-name and production-shaped gates.

use ../../core/array

+ Array
  # V1 follows the current C handlers literally: allocate the ordinary
  # polymorphic result first, reread the receiver's live size at the loop
  # header, decode through Array#[], and append through Array#push.
  -> __w_compact_v1
    out = []
    i = 0
    while i < $size
      value = self[i]
      # The compiler lowers comparison with the nil sentinel to one raw icmp;
      # this is the exact `value != W_NIL` test in w_ic_array_compact, not a
      # user-dispatched equality call.
      if value != nil
        out.push(value)
      i += 1
    out

  -> __w_dup_v1
    out = []
    i = 0
    while i < $size
      out.push(self[i])
      i += 1
    out

  # No operation inside either loop can mutate the receiver. V2 snapshots
  # its raw i32 size once, removing a header load from every backedge while
  # preserving the C result, order, decoding, capacity growth, and errors.
  -> __w_compact_v2
    out = []
    n = $size ## i64
    i = 0
    while i < n
      value = self[i]
      if value != nil
        out.push(value)
      i += 1
    out

  -> __w_dup_v2
    out = []
    n = $size ## i64
    i = 0
    while i < n
      out.push(self[i])
      i += 1
    out
