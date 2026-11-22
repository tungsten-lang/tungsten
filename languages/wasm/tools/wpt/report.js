// Report testharness results: one line per subtest, then a summary.
var __wpt_pass = 0, __wpt_fail = 0;
add_result_callback(function (t) {
  if (t.status === 0) { __wpt_pass++; }
  else { __wpt_fail++; print("  FAIL " + t.name + ": " + t.message); }
});
add_completion_callback(function (tests, status) {
  print("WPT " + __wpt_pass + "/" + (__wpt_pass + __wpt_fail) + (status.status ? " harness status " + status.status + " " + status.message : ""));
});
setup({ explicit_timeout: true, explicit_done: true });
