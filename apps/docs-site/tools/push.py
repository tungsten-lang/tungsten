#!/usr/bin/env python3
"""push.py <app> <file>[=<dest>] ... — write local files into a yaks.app app through the MCP door."""
import base64, json, os, sys, urllib.request
tok = os.environ['YAKS_TOKEN']  # mint one with the yaks.app `grant` tool; never commit it
TEXT = ('.html', '.css', '.js', '.mjs', '.json', '.md', '.txt', '.svg', '.jsonc')
def call(name, args):
    req = urllib.request.Request('https://yaks.app/mcp', data=json.dumps({"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": name, "arguments": args}}).encode(),
                                 headers={'authorization': 'Bearer ' + tok, 'content-type': 'application/json', 'accept': 'application/json, text/event-stream'})
    body = urllib.request.urlopen(req, timeout=300).read().decode()
    if body.startswith('event:') or body.startswith('data:'):
        body = [l[5:] for l in body.split('\n') if l.startswith('data:')][-1]
    return json.loads(body)
app = sys.argv[1]
for spec in sys.argv[2:]:
    src, _, dest = spec.partition('=')
    dest = dest or os.path.basename(src)
    raw = open(src, 'rb').read()
    f = {'path': dest}
    if dest.endswith(TEXT): f['content'] = raw.decode()
    else: f['base64'] = base64.b64encode(raw).decode()
    r = call('app_files', {'app': app, 'files': [f]})
    txt = json.dumps(r.get('result', r))[:300]
    print(dest, len(raw), '->', txt)
