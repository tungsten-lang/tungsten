# Independent stress coverage for the compiler's inline Array iterator CFG.
# Every iterator body owns a lexical recycle scope. Normal continuation,
# predicate short-circuit, break, next, raise, and non-local return must each
# leave that scope exactly once.

-> check_inline_recycle(name, got, want)
  if got != want
    << "FAIL inline recycle " + name + " got=" + got.to_s() + " want=" + want.to_s()
    exit(1)
  << "PASS inline recycle " + name

-> inline_each_control
  seen = []
  [1, 2, 3, 4, 5].each -> (item)
    scratch = [] ## recycle
    scratch.push(item)
    if item == 2
      next
    if item == 5
      break
    seen.push(scratch[0])
  seen

-> inline_predicates
  values = [1, 2, 3, 4]
  all_small = values.all? -> (item)
    scratch = {} ## recycle
    scratch["item"] = item
    scratch["item"] < 5
  any_three = values.any? -> (item)
    scratch = [] ## recycle
    scratch.push(item)
    scratch[0] == 3
  none_large = values.none? -> (item)
    scratch = {} ## recycle
    scratch["item"] = item
    scratch["item"] > 8
  found = values.find -> (item)
    scratch = [] ## recycle
    scratch.push(item)
    scratch[0] == 3
  return [all_small, any_three, none_large, found]

-> inline_predicate_next_break
  any_seen = []
  any_result = [1, 2, 3, 4].any? -> (item)
    scratch = [] ## recycle
    scratch.push(item)
    if item == 2
      next
    any_seen.push(item)
    scratch[0] == 3

  all_seen = []
  all_result = [1, 2, 3, 4].all? -> (item)
    scratch = {} ## recycle
    scratch["item"] = item
    if item == 3
      break
    all_seen.push(item)
    scratch["item"] < 10
  return [any_result, any_seen, all_result, all_seen]

-> inline_raise
  seen = []
  caught = false
  begin
    [1, 2, 3].each -> (item)
      scratch = {} ## recycle
      scratch["item"] = item
      seen.push(item)
      if item == 2
        raise "inline iterator recycle probe"
  rescue error
    caught = true
  return [caught, seen]

-> inline_nonlocal_return(take_return)
  before = [] ## recycle
  before.push(40)
  [1, 2, 3].each -> (item)
    scratch = {} ## recycle
    scratch["item"] = item
    if take_return && item == 2
      return before[0] + scratch["item"]
  later = {} ## recycle
  later["value"] = before[0] + 4
  later["value"]

-> inline_empty_defaults
  values = []
  each_result = values.each -> (item)
    scratch = [] ## recycle
    scratch.push(item)
  all_result = values.all? -> (item)
    scratch = [] ## recycle
    scratch.push(item)
    false
  any_result = values.any? -> (item)
    scratch = {} ## recycle
    scratch["item"] = item
    true
  none_result = values.none? -> (item)
    scratch = [] ## recycle
    scratch.push(item)
    true
  find_result = values.find -> (item)
    scratch = {} ## recycle
    scratch["item"] = item
    true
  return [each_result == values, all_result, any_result, none_result, find_result]

-> inline_param_shadows_unboxed
  observed = []
  item = 0
  while item < 1
    [7].each -> (item)
      observed.push(item)
    item += 1
  observed[0]

-> inline_preserves_outer_unboxed
  total = 0
  i = 0
  while i < 1
    [2, 3].each -> (item)
      total += item
    i += 1
  total

-> inline_preserves_raw_param(value) (i64) i64
  [1].each -> (item)
    scratch = [] ## recycle
    scratch.push(item)
  value + 1

-> recycled_array_pair_distinct
  first = [] ## recycle
  second = [] ## recycle
  wvalue_bits(first) != wvalue_bits(second)

-> recycled_hash_pair_distinct
  first = {} ## recycle
  second = {} ## recycle
  wvalue_bits(first) != wvalue_bits(second)

each_seen = inline_each_control()
check_inline_recycle("each size", each_seen.size(), 3)
check_inline_recycle("each first", each_seen[0], 1)
check_inline_recycle("each next", each_seen[1], 3)
check_inline_recycle("each break", each_seen[2], 4)

predicates = inline_predicates()
check_inline_recycle("all?", predicates[0], true)
check_inline_recycle("any?", predicates[1], true)
check_inline_recycle("none?", predicates[2], true)
check_inline_recycle("find", predicates[3], 3)

controls = inline_predicate_next_break()
check_inline_recycle("predicate next result", controls[0], true)
check_inline_recycle("predicate next seen size", controls[1].size(), 2)
check_inline_recycle("predicate next seen last", controls[1][1], 3)
check_inline_recycle("predicate break default", controls[2], true)
check_inline_recycle("predicate break seen size", controls[3].size(), 2)

raised = inline_raise()
check_inline_recycle("raise caught", raised[0], true)
check_inline_recycle("raise seen size", raised[1].size(), 2)
check_inline_recycle("nonlocal return", inline_nonlocal_return(true), 42)
check_inline_recycle("normal return", inline_nonlocal_return(false), 44)

empty = inline_empty_defaults()
check_inline_recycle("empty each", empty[0], true)
check_inline_recycle("empty all?", empty[1], true)
check_inline_recycle("empty any?", empty[2], false)
check_inline_recycle("empty none?", empty[3], true)
check_inline_recycle("empty find", empty[4], nil)
check_inline_recycle("param shadows outer unboxed", inline_param_shadows_unboxed(), 7)
check_inline_recycle("outer unboxed update", inline_preserves_outer_unboxed(), 5)
check_inline_recycle("outer raw param binding", inline_preserves_raw_param(41), 42)

i = 0
while i < 32
  inline_each_control()
  inline_predicates()
  inline_predicate_next_break()
  inline_raise()
  inline_nonlocal_return(true)
  i += 1
check_inline_recycle("array pool distinct", recycled_array_pair_distinct(), true)
check_inline_recycle("hash pool distinct", recycled_hash_pair_distinct(), true)

<< "PASS inline iterator recycle validation"
