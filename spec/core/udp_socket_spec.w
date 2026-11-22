# UDPSocket (core/udp_socket.w) over loopback: a server bound on an ephemeral
# port, a connected client, recv_from and a send_to reply; byte-exact binary
# datagrams (0x00 and 0xff, String and ByteArray, up to 60000 bytes); one
# datagram per recv with truncation to max; a recv timeout answering nil; a
# connected socket hearing ICMP port-unreachable; resolution by name; IPv6
# where the host has ::1; close idempotent. Fiber parking is in
# udp_socket_park_spec.w.
#
# Also runs on the Ruby implementation (bin/tungsten --ruby), which has no
# spec lane of its own.

-> check(name, condition)
  if !condition
    << "FAIL " + name
    exit(1)

-> raised(block)
  begin
    block.call()
  rescue e
    return "" + e.to_s
  nil

server = UDPSocket.new()
check("bind.returns.self", server.bind("127.0.0.1", 0) == server)
port = server.local_port
check("bind.ephemeral.port", port > 0)
check("family.default", server.family == :ipv4)

# A connected client: "localhost" resolves like Socket.connect.
client = UDPSocket.new().connect("localhost", port)
check("send.count", client.send("ping") == 4)
got = server.recv_from()
check("recv_from.data", got[0] == "ping")
check("recv_from.host", got[1] == "127.0.0.1")
check("recv_from.port", got[2] == client.local_port)
check("send_to.count", server.send_to("pong", got[1], got[2]) == 4)
check("recv.reply", client.recv() == "pong")

# Binary datagrams keep every byte, NULs and 0xff included.
payload = « 00 ff 41 00 7f 80 00 »
expected = [0, 255, 65, 0, 127, 128, 0]
client.send(payload)
text = server.recv()
check("recv.binary.string", text.bytes.to_a == expected)
client.send(payload)
bytes = server.recv_bytes()
check("recv_bytes.size", bytes.size == 7)
check("recv_bytes.exact", bytes == payload)
client.send(text)
check("send.binary.string", server.recv_bytes() == payload)
client.send(payload)
from = server.recv_from()
check("recv_from.binary", from[0].bytes.to_a == expected)

big = ByteArray.new(60000)
big[0] = 7
big[30000] = 0xff
big[59999] = 1
check("send.large", client.send(big) == 60000)
large = server.recv_bytes()
check("recv.large.size", large.size == 60000)
check("recv.large.bytes", large[0] == 7 && large[30000] == 255 && large[59999] == 1)

# One datagram per recv; a longer one is truncated to max.
client.send("abc")
client.send("defgh")
check("recv.one.datagram", server.recv() == "abc")
check("recv.truncates", server.recv(2) == "de")

# A recv timeout answers nil instead of waiting forever.
check("set_timeout.returns.self", client.set_timeout(100) == client)
check("recv.timeout.nil", client.recv() == nil)
check("recv_from.timeout.nil", client.recv_from() == nil)
check("recv_bytes.timeout.nil", client.recv_bytes() == nil)

# A connected socket hears ICMP port-unreachable from its peer.
probe = UDPSocket.new().bind("127.0.0.1", 0)
dead_port = probe.local_port
probe.close()
lonely = UDPSocket.new().connect("127.0.0.1", dead_port)
lonely.set_timeout(1000)
lonely.send("anyone?")
refused = raised(->() lonely.recv())
check("recv.refused", refused != nil && refused.include?("connection refused"))
lonely.close()

check("resolve.error", raised(->() client.send_to("x", "no-such-host.invalid", 9)).starts_with?("udp: cannot resolve"))
check("send.type.error", raised(->() client.send(42)) != nil)
check("family.error", raised(->() UDPSocket.new(:ipx)) != nil)

# IPv6, where the host has a loopback address for it.
v6 = UDPSocket.new(:ipv6)
if raised(->() v6.bind("::1", 0)) == nil
  c6 = UDPSocket.new(:ipv6).connect("::1", v6.local_port)
  c6.send(payload)
  got6 = v6.recv_from()
  check("ipv6.recv_from.data", got6[0].bytes.to_a == expected)
  check("ipv6.recv_from.host", got6[1] == "::1")
  check("ipv6.recv_from.port", got6[2] == c6.local_port)
  c6.close()
v6.close()

# close is idempotent; a closed socket raises rather than reusing its fd.
check("open.not.closed", !client.closed?)
check("close.nil", client.close() == nil)
check("close.again.nil", client.close() == nil)
check("closed", client.closed?)
check("closed.send.raises", raised(->() client.send("late")) != nil)
check("closed.recv.raises", raised(->() client.recv()) != nil)
server.close()
server.close()

<< "udp_socket: ok"
