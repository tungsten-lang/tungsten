"""Native encode/verification orchestration; FFmpeg is an independent inspector."""
import json
import pathlib


class Native:
    def __init__(self,toolchain,package,runner):
        self.toolchain=pathlib.Path(toolchain); self.package=pathlib.Path(package); self.runner=runner

    def call(self,command,*args):
        import subprocess
        try: result=self.runner.run([self.toolchain/'bin/tungsten',self.package/'lib/av/native.w','--',command,*args],capture=True)
        except subprocess.CalledProcessError as error:
            if command!='verify': raise
            result=error
        for line in reversed(result.stdout.decode().splitlines()):
            try: return json.loads(line)
            except json.JSONDecodeError: pass
        raise ValueError('native AV bridge returned no JSON: '+result.stdout.decode()[-500:])

    def capabilities(self): return self.call('capabilities')
    def facts(self,path): return self.call('facts',path)

    def probe(self,path):
        result=self.runner.run(['ffprobe','-v','error','-show_streams','-show_format','-of','json',path],capture=True)
        return json.loads(result.stdout)

    def request(self,command,path,options,directory,destination=None):
        from inputs import write_json
        request=pathlib.Path(directory)/(command+'.json')
        write_json(request,dict(source=str(path),destination=str(destination) if destination else None,options=options))
        return self.call(command,request)
