# Live JSON-RPC integration check.
#
# Not part of the default spec run: it needs a node (or the mock in
# scratchpad/mockd.py) listening. Run it against regtest with
#
#   bin/tungsten -o /tmp/rpc_live bits/tungsten-crypto/spec/rpc_live.w
#   /tmp/rpc_live 127.0.0.1 18443 user pass
#
# It exercises the parts unit tests cannot: socket transport, HTTP basic
# auth, request framing, response decoding, and the error path.

use ../lib/crypto

args = argv()
host = "127.0.0.1"
port = 18443
user = "user"
pass = "pass"
if args.size > 0
  host = args[0]
if args.size > 1
  port = args[1].to_i
if args.size > 2
  user = args[2]
if args.size > 3
  pass = args[3]

rpc = BitcoinRPC.new(host, port, user, pass)
fails = 0

count = rpc.getblockcount
<< "getblockcount      -> [count]"
if count == nil
  fails += 1

best = rpc.getbestblockhash
<< "getbestblockhash   -> [best]"
if best == nil
  fails += 1

tmpl = rpc.getblocktemplate
if tmpl == nil
  << "getblocktemplate   -> FAILED"
  fails += 1
else
  << "getblocktemplate   -> height [tmpl["height"]] bits [tmpl["bits"]] value [tmpl["coinbasevalue"]]"
  if tmpl["height"] == nil || tmpl["bits"] == nil
    fails += 1

# A deliberately bad block must come back with the node's rejection reason
# rather than being silently treated as accepted.
reply = rpc.submitblock("deadbeef")
<< "submitblock(bad)   -> [reply]"
if reply == nil
  << "  EXPECTED a rejection reason, got nil (would be read as accepted)"
  fails += 1

# An RPC-level error must surface as nil, not as a bogus result.
err = rpc.call("boom", "\[\]")
<< "error method       -> [err] (want nil)"
if err != nil
  fails += 1

<< ""
if fails == 0
  << "rpc: all checks passed"
  exit(0)
<< "rpc: [fails] checks failed"
exit(1)
