use ../../lib/hashing
use ../../lib/target

today = ccall("w_date_today")
entry = {
  version: "target-probe-v1",
  key: "expected",
  day: today,
  datalayout: "layout",
  triple: "triple",
  fn_attrs: ""
}

if !target_probe_cache_entry_valid?(entry, "expected")
  raise "current-day target probe entry was rejected"

entry[:day] = nil
if target_probe_cache_entry_valid?(entry, "expected")
  raise "expired target probe entry was accepted"

entry[:day] = today
if target_probe_cache_entry_valid?(entry, "different")
  raise "wrong-key target probe entry was accepted"

entry[:datalayout] = ""
if target_probe_cache_entry_valid?(entry, "expected")
  raise "incomplete target probe entry was accepted"

<< "target probe cache validation: PASS"
