use core/system

count = System.cpu_count ## i64
if count < 1
  << "system cpu_count FAILED"
  exit(1)
<< "system cpu_count ok: " + count.to_s()
