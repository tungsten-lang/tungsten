use ../lib/metaflip/rect/campaign

failures = 0 ## i64

-> expect(actual, wanted, label) (i64 i64 String) i64
  if actual == wanted
    << "PASS " + label
    return 0
  << "FAIL " + label + " actual=" + actual.to_s() + " wanted=" + wanted.to_s()
  1

failures += expect(ffrc_side_archive_enabled(0,0,0-1,1),0,"unsalted standalone preserves historical behavior")
failures += expect(ffrc_side_archive_enabled(1,91,7,1),1,"portfolio child archives endpoints")
failures += expect(ffrc_side_archive_enabled(0,91,0-1,1),1,"salted standalone archives endpoints")
failures += expect(ffrc_side_archive_enabled(0,0,7,1),1,"door-scheduled standalone archives endpoints")
failures += expect(ffrc_side_archive_enabled(1,91,7,0),0,"explicit seed remains isolated")
failures += expect(ffrc_frontier_rank_eligible(29,29),1,"record-rank frontier remains eligible")
failures += expect(ffrc_frontier_rank_eligible(31,29),1,"R+2 frontier remains eligible")
failures += expect(ffrc_frontier_rank_eligible(31,28),0,"stale R+3 frontier is filtered after a rank win")
failures += expect(ffrc_frontier_rank_eligible(27,28),0,"frontier below the durable leader is filtered")

if failures != 0
  exit(1)
<< "PASS rectangular shard archive policy"
