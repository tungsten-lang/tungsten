ch = Channel.new(1)
go -> ch.send(42)
<< ch.recv()
