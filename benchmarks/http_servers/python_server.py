import asyncio

RESPONSE = b"HTTP/1.1 200 OK\r\nContent-Length: 12\r\nConnection: keep-alive\r\n\r\nHello World\n"

class HelloProtocol(asyncio.Protocol):
    def connection_made(self, transport):
        self.transport = transport
    def data_received(self, data):
        self.transport.write(RESPONSE)

async def main():
    loop = asyncio.get_event_loop()
    server = await loop.create_server(HelloProtocol, "0.0.0.0", 8080, reuse_address=True, reuse_port=False)
    await server.serve_forever()

asyncio.run(main())
