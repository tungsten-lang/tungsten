# https://rosettacode.org/wiki/Hello_world/Web_server#Ruby

# @todo finish

use web

server = Web:Server.new(port: 8080)
server.get('/')
server.start

## expect skip server example
