# Test assertion helpers for boot1

pass_count = 0
fail_count = 0
current_test = ""

-> assert_eq(actual, expected)
  if actual == expected
    pass_count += 1
  else
    fail_count += 1
    << "FAIL: [current_test]"
    << "  expected: [expected]"
    << "  actual:   [actual]"

-> assert_true(value)
  assert_eq value, true

-> assert_false(value)
  assert_eq value, false

-> assert_nil(value)
  assert_eq value, nil

-> test(name)
  current_test = name

-> report
  total = pass_count + fail_count
  << "[pass_count]/[total] passed"
  if fail_count > 0
    << "[fail_count] FAILED"
    exit 1
