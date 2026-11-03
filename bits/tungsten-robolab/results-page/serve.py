"""Serve only the portable results export, with byte ranges for video seeking."""
from http.server import SimpleHTTPRequestHandler,ThreadingHTTPServer
from pathlib import Path
import argparse,functools,re
class Handler(SimpleHTTPRequestHandler):
    def send_head(self):
        self.remaining=None
        path=Path(self.translate_path(self.path))
        if self.headers.get('Range') and path.is_file():
            size=path.stat().st_size;match=re.fullmatch(r'bytes=(\d+)-(\d*)',self.headers['Range'])
            if match:
                start=int(match[1]);end=min(int(match[2]) if match[2] else size-1,size-1)
                if start>=size or start>end:
                    self.send_response(416);self.send_header('Content-Range',f'bytes */{size}');self.end_headers();return None
                f=path.open('rb');f.seek(start);self.remaining=end-start+1
                self.send_response(206);self.send_header('Content-Type',self.guess_type(str(path)));self.send_header('Accept-Ranges','bytes');self.send_header('Content-Range',f'bytes {start}-{end}/{size}');self.send_header('Content-Length',str(self.remaining));self.end_headers();return f
        return super().send_head()
    def copyfile(self,source,output):
        if self.remaining is None:return super().copyfile(source,output)
        while self.remaining:
            part=source.read(min(self.remaining,65536))
            if not part:break
            output.write(part);self.remaining-=len(part)
    def log_message(self,*args):pass
if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--port',type=int,default=8769);a=ap.parse_args()
    server=ThreadingHTTPServer(('127.0.0.1',a.port),functools.partial(Handler,directory=str(Path(__file__).resolve().parent/'dist')))
    print(f'Results page: http://127.0.0.1:{server.server_port}',flush=True);server.serve_forever()
