begin
  raise "oops"
rescue e
  << "caught: " + e
ensure
  << "cleanup"
