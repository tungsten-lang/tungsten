# UDPSocket#recv parks its fiber on the event loop instead of blocking the
# process: a goroutine waits in recv while a later goroutine sends it the
# datagram, and a second waiter times out on its deadline while parked.
#
# A goroutine runs when main blocks or in the end-of-main drain, and the
# scheduler polls the event loop only when no goroutine is runnable (a main-
# thread Channel#receive runs runnable goroutines but polls no fds, and a
# goroutine spinning in Channel#receive keeps the run queue busy), so the
# goroutines record into a shared array and the last one checks it.
# If recv blocked the process, the sender could not run until the receiver's
# 3 s deadline passed and the receiver would see nil.
#
# The Ruby implementation has no `go`, so this spec runs compiled and
# interpreted only; udp_socket_spec.w covers UDPSocket there.

-> check(name, condition)
  if !condition
    << "FAIL " + name
    exit(1)

+ Probe
  -> .receive(server, events)
    events.push("recv-start")
    data = server.recv()
    check("park.recv.data", data == "parked")
    events.push("recv-done")

  -> .transmit(client, events)
    events.push("send")
    client.send("parked")

  # Parked longest (its 200 ms deadline), so it checks the whole order.
  -> .expire(quiet, events)
    data = quiet.recv()
    check("park.timeout.nil", data == nil)
    events.push("timeout")
    check("park.order", events == ["recv-start", "send", "recv-done", "timeout"])
    << "udp_socket_park: ok"

server = UDPSocket.new().bind("127.0.0.1", 0)
server.set_timeout(3000)
client = UDPSocket.new().connect("127.0.0.1", server.local_port)
quiet = UDPSocket.new().bind("127.0.0.1", 0)
quiet.set_timeout(200)
events = []

go -> Probe.receive(server, events)
go -> Probe.transmit(client, events)
go -> Probe.expire(quiet, events)
