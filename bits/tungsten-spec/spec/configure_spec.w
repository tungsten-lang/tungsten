use spec

configured = false
TungstenSpec.configure ->
  configured = true

if !configured
  << "FAIL TungstenSpec.configure did not run its block"
  exit 1

<< "PASS TungstenSpec.configure"
