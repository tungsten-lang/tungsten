use ../lib/metaflip/rect/campaign

failures = 0 ## i64

if ffrc_live_status_due(0, 1000, 1001) != 1
  << "FAIL standalone status must remain due every round"
  failures += 1
if ffrc_live_status_due(1, 0 - 1, 1000) != 1
  << "FAIL first portfolio-child status must be written"
  failures += 1
if ffrc_live_status_due(1, 1000, 1199) != 0
  << "FAIL portfolio-child status should be suppressed before 200 ms"
  failures += 1
if ffrc_live_status_due(1, 1000, 1200) != 1
  << "FAIL portfolio-child status must be due at 200 ms"
  failures += 1
if ffrc_live_status_due(1, 1000, 1301) != 1
  << "FAIL overdue portfolio-child status must be written"
  failures += 1

if failures != 0
  exit(1)

<< "PASS rectangular child live-status cadence"
