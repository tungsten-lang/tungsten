"""Declarative AV directives in a project-root Bitfile; never eval project code."""
from __future__ import annotations
import dataclasses
import hashlib
import os
import fractions
import json
import math
import pathlib
import re


class ConfigError(ValueError):
    pass


TOKEN = re.compile(r'''\s*(?:(\#.*)|("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')|([+-]?(?:\d+\.\d+|\d+)(?:[eE][+-]?\d+)?)|([A-Za-z_][A-Za-z0-9_.-]*)|([\[\]{},:]))''')


class Literals:
    def __init__(self, text):
        self.tokens=[]; position=0
        while position<len(text):
            if not text[position:].strip(): break
            match=TOKEN.match(text,position)
            if not match: raise ConfigError('expected a literal near '+repr(text[position:position+32]))
            position=match.end()
            if match[1]: break
            self.tokens.append(next((i,v) for i,v in enumerate(match.groups(),1) if v is not None))
        self.index=0

    def peek(self, value=None):
        token=self.tokens[self.index][1] if self.index<len(self.tokens) else None
        return token if value is None else token==value

    def take(self, expected=None):
        if self.index>=len(self.tokens): raise ConfigError('incomplete directive')
        kind,value=self.tokens[self.index]; self.index+=1
        if expected is not None and value!=expected: raise ConfigError(f'expected {expected!r}, got {value!r}')
        return kind,value

    def value(self, depth=0):
        if depth>16: raise ConfigError('Bitfile literal nesting exceeds 16')
        kind,value=self.take()
        if kind==2:
            if value.startswith('"'): return json.loads(value)
            # Tungsten single quotes support literal text and escaped quotes/backslashes.
            return re.sub(r"\\(['\\])",r'\1',value[1:-1])
        if kind==3:
            result=float(value) if any(c in value for c in '.eE') else int(value)
            if isinstance(result,float) and not math.isfinite(result): raise ConfigError('numbers must be finite')
            return result
        if value==':':
            k,name=self.take()
            if k not in (2,4): raise ConfigError('expected a symbol name')
            return json.loads(name) if name.startswith('"') else name
        if value=='[':
            result=[]
            while not self.peek(']'):
                result.append(self.value(depth+1))
                if not self.peek(','): break
                self.take(',')
            self.take(']'); return result
        if value=='{':
            result={}
            while not self.peek('}'):
                k,key=self.take()
                if k not in (2,4): raise ConfigError('expected a hash key')
                key=json.loads(key) if key.startswith('"') else (re.sub(r"\\(['\\])",r'\1',key[1:-1]) if key.startswith("'") else key)
                self.take(':')
                if key in result: raise ConfigError('duplicate key: '+key)
                result[key]=self.value(depth+1)
                if not self.peek(','): break
                self.take(',')
            self.take('}'); return result
        if value in ('true','false','nil'): return {'true':True,'false':False,'nil':None}[value]
        raise ConfigError('values must be quoted strings, symbols, numbers, booleans, lists or hashes')

    def arguments(self):
        positional=[]; options={}
        while self.peek() is not None:
            is_option=(self.index+1<len(self.tokens) and self.tokens[self.index][0] in (2,4) and self.tokens[self.index+1][1]==':')
            if is_option:
                _,key=self.take(); self.take(':')
                key=json.loads(key) if key.startswith('"') else (re.sub(r"\\(['\\])",r'\1',key[1:-1]) if key.startswith("'") else key)
                if key in options: raise ConfigError('duplicate option: '+key)
                options[key]=self.value()
            else: positional.append(self.value())
            if self.peek() is not None: self.take(',')
        return positional,options


def statements(text):
    """Join multiline literals while keeping package-manager directives untouched."""
    buffer=''; start=0; stack=[]; quote=None; escaped=False
    for number,line in enumerate(text.splitlines(),1):
        if not buffer and not re.match(r'^\s*av\.',line): continue
        if not buffer: start=number
        clean=''
        for char in line:
            if quote:
                clean+=char
                if escaped: escaped=False
                elif char=='\\': escaped=True
                elif char==quote: quote=None
            elif char in ('"',"'"): quote=char; clean+=char
            elif char=='#': break
            else:
                clean+=char
                if char in '[{': stack.append(char)
                elif char in ']}':
                    if not stack or (stack.pop(),char) not in (('[',']'),('{','}')): raise ConfigError(f'line {number}: mismatched delimiter')
        buffer+=' '+clean.strip()
        if not stack and quote is None and not buffer.rstrip().endswith(','):
            yield start,buffer.strip(); buffer=''
    if buffer: raise ConfigError(f'line {start}: incomplete AV directive')


FIELDS={
 'project': {'source','timeline','cut','mix','toolchain','workspace','cache','snapshot_inputs','timecode','generator_clock','scene_rate','title'},
 'output': {'path','role','from','source','format','width','height','rate','fit','filter','start_frame','frames','faststart','edit_lists','timeline','cut','mix'},
 'video': {'codec','bitrate','quality','depth','chroma','level','gop','reorder','speed','backend','crop','rect'},
 'audio': {'codec','bitrate','sample_format','sample_rate','channels','layout','source'},
 'colour': {'primaries','transfer','matrix','range','untagged'},
 'subtitles': {'profile','language','mode'},
 'chapters': {'profile','format'},
 'loudness': {'enabled','target','tolerance','true_peak','max_clipped_samples','max_silence','silence_threshold','max_channel_difference'},
 'text': {'enabled','font','size','minimum_size','box','safe_area','foreground','background','minimum_contrast','burned','minimum_edge_recall','max_error'},
 'anomalies': {'enabled','black_min','freeze_min','noise','allow_black','allow_freeze','policy'},
 'resources': {'memory_mb','disk_reserve_mb','jobs','animation_jobs','decode_ahead','segments_ahead','timeout','native_timeout_ms','retries','cache_days'},
 'quality': {'mode','minimum_bitrate','maximum_bitrate','max_probes','probe_frames','minimum_ssim','minimum_vmaf','sample_frames'},
 'banding': {'auto','background','gradient','samples','limits','exclude','exclude_normalized','shots','max_samples','asset_prefix','program_id'},
 'publish': {'root','layout','profiles','files','release_dir'},
 'prepare': {'argv','cwd'},
 'input': {'path','generated'},
 'gate': {'pattern','equal','profile'},
}
PER_PROFILE={'output','video','audio','colour','loudness','text','anomalies','quality','banding'}
NAME=re.compile(r'^[a-z][a-z0-9_-]{0,63}$')


def bitrate(value):
    if value is None: return None
    if type(value) is int and value>0: return value
    if isinstance(value,str):
        match=re.fullmatch(r'(\d+(?:\.\d+)?)\s*([kKmM]?)',value)
        if match:
            result=fractions.Fraction(match[1])*{'':1,'k':1000,'m':1000000}[match[2].lower()]
            if result.denominator==1 and result>0: return result.numerator
    raise ConfigError('bitrate must be positive bits/second, e.g. 1800000 or "1800k"')


def positive(value,name,allow_zero=False):
    if isinstance(value,bool) or not isinstance(value,(int,float)) or (isinstance(value,float) and not math.isfinite(value)) or (value<0 if allow_zero else value<=0):
        raise ConfigError(name+' must be a finite '+('nonnegative' if allow_zero else 'positive')+' number')
    return value


@dataclasses.dataclass
class Project:
    root: pathlib.Path
    file: pathlib.Path
    name: str
    settings: dict
    declarations: dict
    content_sha256: str

    @classmethod
    def load(cls,directory):
        path=pathlib.Path(directory).expanduser().resolve()
        if path.is_file():
            if path.name!='Bitfile': raise ConfigError('project configuration must be named Bitfile')
        else:
            while not (path/'Bitfile').is_file():
                if path.parent==path: raise ConfigError('No project Bitfile found; run bit av init')
                path=path.parent
            path=path/'Bitfile'
        if path.stat().st_size>1024*1024: raise ConfigError('Bitfile is too large')
        content=path.read_bytes()
        declarations={key:[] for key in FIELDS}
        for line,statement in statements(content.decode('utf-8')):
            method,_,arguments=statement.partition(' '); kind=method[3:]
            try:
                if kind not in FIELDS: raise ConfigError('unknown AV directive: '+method)
                args,options=Literals(arguments).arguments()
                unknown=set(options)-FIELDS[kind]
                if unknown: raise ConfigError('unknown '+method+' options: '+', '.join(sorted(unknown)))
                if kind=='resources':
                    if args: raise ConfigError('av.resources accepts keyword options')
                    label='all'
                else:
                    if len(args)!=1 or not isinstance(args[0],str): raise ConfigError(method+' expects one name/path and keyword options')
                    label=args[0]
                declarations[kind].append(dict(name=label,**options))
            except (ValueError,KeyError) as error:
                raise ConfigError(f'{path}:{line}: {error}') from error
        if len(declarations['project'])!=1: raise ConfigError('Bitfile must contain exactly one av.project directive')
        settings=dict(declarations['project'][0]); name=settings.pop('name')
        if not NAME.fullmatch(name): raise ConfigError('project name must use lowercase letters, digits, underscores or hyphens')
        if bool(settings.get('source'))==bool(settings.get('timeline')): raise ConfigError('av.project requires exactly one source: or timeline:')
        for kind,items in declarations.items():
            for item in items:
                for key in ('path','from','source','timeline','cut','mix','format','role','font','language','mode','policy','layout','root','release_dir','cwd'):
                    if key in item and not isinstance(item[key],str): raise ConfigError(kind+'.'+key+' must be a string or symbol')
        project=cls(path.parent,path,name,settings,declarations,hashlib.sha256(content).hexdigest())
        project.validate()
        project.resources()
        project.profiles()  # validate profiles before any stage can write media
        return project

    def path(self,value):
        path=pathlib.Path(value).expanduser()
        return path.resolve() if path.is_absolute() else (self.root/path).resolve()

    def output_path(self,value):
        path=pathlib.Path(value).expanduser()
        path=path if path.is_absolute() else self.root/path
        return path.parent.resolve()/path.name

    @property
    def workspace(self): return self.path(self.settings.get('workspace','.av'))

    @property
    def toolchain(self):
        import os
        value=os.environ.get('STUDIO_TW') or self.settings.get('toolchain') or os.environ.get('TUNGSTEN_ROOT')
        if not value: raise ConfigError('select an isolated toolchain with av.project toolchain:')
        return self.path(value)

    def profiles(self):
        outputs=self.declarations['output'] or [dict(name='master')]
        names=[item['name'] for item in outputs]
        if len(set(names))!=len(names) or any(not NAME.fullmatch(n) for n in names): raise ConfigError('output profile names must be unique simple names')
        for kind in PER_PROFILE-{'output'}:
            labels=[entry['name'] for entry in self.declarations[kind]]
            if len(set(labels))!=len(labels): raise ConfigError('duplicate av.'+kind+' profile')
            if set(labels)-set(names)-{'all'}: raise ConfigError('unknown profile in av.'+kind)
        profiles={}
        for output in outputs:
            name=output['name']; profile=dict(output)
            if not profile.get('timeline') and ('cut' in profile or 'mix' in profile): raise ConfigError('output cut/mix require an alternate timeline')
            if profile.get('timeline') and profile.get('from'): raise ConfigError('an output must choose timeline: or from:')
            profile.setdefault('role',name if name in ('master','share','short') else 'master')
            profile.setdefault('format','mp4' if profile['role']=='share' else 'mov')
            if profile['format'] not in ('mov','mp4'): raise ConfigError('video container format must be mov or mp4')
            profile.setdefault('path','render/'+name+'.'+profile['format'])
            if pathlib.Path(profile['path']).suffix.lower()!='.'+profile['format']: raise ConfigError('output extension must match format: '+profile['path'])
            for kind in PER_PROFILE-{'output'}:
                settings={}
                for label in ('all',name):
                    for item in self.declarations[kind]:
                        if item['name']==label: settings.update({k:v for k,v in item.items() if k!='name'})
                profile[kind]=settings
            video=profile['video']; video.setdefault('codec','hevc10'); codec=video['codec']
            if codec not in ('h264','hevc','hevc10','prores422','prores422hq','prores422lt','prores422proxy'): raise ConfigError('unsupported video codec: '+str(codec))
            video.setdefault('depth',10 if codec=='hevc10' or codec.startswith('prores') else 8)
            video.setdefault('chroma','422' if codec.startswith('prores') else '420'); video['chroma']=str(video['chroma'])
            if video['depth']!=(10 if codec=='hevc10' or codec.startswith('prores') else 8): raise ConfigError('codec/depth conflict for '+name)
            if video['chroma']!=('422' if codec.startswith('prores') else '420'): raise ConfigError('codec/chroma conflict for '+name)
            if 'bitrate' in video: video['bitrate']=bitrate(video['bitrate'])
            if 'quality' in video and (type(video['quality']) not in (int,float) or not 0<=video['quality']<=1): raise ConfigError('quality must be in 0..1')
            if 'quality' in video and 'bitrate' in video: raise ConfigError('choose video quality or bitrate for '+name)
            if codec.startswith('prores') and 'bitrate' in video: raise ConfigError('ProRes uses quality rather than a target bitrate')
            for dimension in ('width','height','frames'):
                if dimension in profile:
                    if type(profile[dimension]) is not int or profile[dimension]<=0: raise ConfigError(dimension+' must be a positive integer')
                    if dimension!='frames' and (profile[dimension]%2 or profile[dimension]>16384): raise ConfigError(dimension+' must be even and <= 16384')
            if 'rate' in profile:
                value=profile['rate']
                if not isinstance(value,list) or len(value)!=2 or any(type(x)is not int or x<=0 for x in value): raise ConfigError('rate must be [positive numerator, positive denominator]')
                f=fractions.Fraction(*value); profile['rate']=[f.numerator,f.denominator]
            audio=profile['audio']; audio.setdefault('codec','aac' if profile['format']=='mp4' else 'pcm')
            if audio['codec'] not in ('aac','pcm','copy','none'): raise ConfigError('audio codec must be aac, pcm, copy or none')
            audio.setdefault('sample_format','s24le'); audio.setdefault('sample_rate',48000); audio.setdefault('channels',2)
            if audio['sample_format'] not in ('s16le','s24le','s32le','f32le'): raise ConfigError('unsupported PCM sample_format')
            if type(audio['sample_rate']) is not int or type(audio['channels']) is not int or audio['sample_rate'] not in (32000,44100,48000,88200,96000) or audio['channels'] not in (1,2): raise ConfigError('audio sample_rate/channels unsupported')
            if audio.get('layout', 'mono' if audio['channels']==1 else 'stereo') != ('mono' if audio['channels']==1 else 'stereo'): raise ConfigError('audio layout conflicts with channels')
            if audio['codec']=='pcm' and profile['format']!='mov': raise ConfigError('PCM delivery requires MOV')
            if 'bitrate' in audio:
                if audio['codec']!='aac': raise ConfigError('an audio bitrate is supported for AAC only')
                audio['bitrate']=bitrate(audio['bitrate'])
                if audio['bitrate']%1000: raise ConfigError('AAC bitrate must be a whole number of kbps')
            profile.setdefault('edit_lists',False if profile['format']=='mov' and audio['codec'] in ('pcm','none') else True)
            if profile['edit_lists'] is False and audio['codec'] not in ('pcm','none'): raise ConfigError('strict no-edit audio requires PCM MOV')
            colour=profile['colour']
            for key in ('primaries','transfer','matrix'): colour.setdefault(key,'bt709')
            colour.setdefault('range','limited'); colour.setdefault('untagged','reject')
            if any(colour[k]!='bt709' for k in ('primaries','transfer','matrix')) or colour['range']!='limited': raise ConfigError('this renderer delivers BT.709 limited-range SDR; unsupported colour contracts are rejected')
            if colour['untagged'] not in ('reject','bt709'): raise ConfigError('untagged must be reject or bt709')
            if profile['quality'].get('mode','fixed') not in ('fixed','search'): raise ConfigError('quality mode must be fixed or search')
            if profile['quality'].get('mode')=='search' and codec.startswith('prores'): raise ConfigError('bitrate search requires H.264 or HEVC')
            for key in ('minimum_bitrate','maximum_bitrate'):
                if key in profile['quality']: profile['quality'][key]=bitrate(profile['quality'][key])
            for kind in ('loudness','text','anomalies'):
                profile[kind].setdefault('enabled',False)
            profiles[name]=profile
        pending=dict(profiles); ordered={}
        while pending:
            ready=[name for name,p in pending.items() if not p.get('from') or p['from'] in ordered]
            if not ready: raise ConfigError('unknown or cyclic output from: dependency')
            for name in ready: ordered[name]=pending.pop(name)
        targets=[self.output_path(p['path']) for p in ordered.values()]
        if len(set(targets))!=len(targets): raise ConfigError('output paths must be unique')
        if self.settings.get('source') and self.path(self.settings['source']) in targets: raise ConfigError('an output would overwrite the source')
        for kind in ('subtitles','chapters','gate'):
            for item in self.declarations[kind]:
                if item.get('profile','all') not in set(names)|{'all'}: raise ConfigError('unknown '+kind+' profile')
                if kind=='subtitles' and item.get('language') and not re.fullmatch(r'[A-Za-z]{2,8}(?:-[A-Za-z0-9]{1,8})*',item['language']): raise ConfigError('subtitle language must be a language tag')
                if kind=='subtitles' and item.get('mode','sidecar') not in ('sidecar','timeline'): raise ConfigError('subtitles mode must be sidecar or timeline (burned by a timeline project)')
                if kind=='subtitles' and item.get('mode')=='timeline' and not self.settings.get('timeline'): raise ConfigError('timeline subtitle burning requires a timeline project')
        return ordered

    def validate(self):
        if self.settings.get('snapshot_inputs',True) is not True: raise ConfigError('snapshot_inputs must be true; immutable inputs are required for reproducible jobs')
        for key in ('source','timeline','mix','toolchain','workspace','cache','title'):
            if key in self.settings and (not isinstance(self.settings[key],str) or not self.settings[key]): raise ConfigError('project.'+key+' requires a nonempty string')
        if not self.workspace.is_relative_to(self.root) or self.workspace==self.root or '.git' in self.workspace.relative_to(self.root).parts: raise ConfigError('workspace must be a dedicated subdirectory inside the project')
        if 'cache' in self.settings:
            cache=self.path(self.settings['cache'])
            if not cache.is_relative_to(self.workspace): raise ConfigError('cache must be inside the AV workspace')
        for kind in ('project','resources'):
            if len(self.declarations[kind])>1: raise ConfigError('duplicate av.'+kind)
        for kind in ('prepare','publish','input'):
            labels=[item['name'] for item in self.declarations[kind]]
            if len(labels)!=len(set(labels)): raise ConfigError('duplicate av.'+kind+' name')
        for item in self.declarations['prepare']:
            argv=item.get('argv')
            if not isinstance(argv,list) or not argv or any(not isinstance(v,str) or '\0' in v for v in argv): raise ConfigError('prepare argv must be a nonempty string array')
        profiles=self.profiles()
        for name,p in profiles.items():
            for key in ('edit_lists','faststart'):
                if key in p and type(p[key]) is not bool: raise ConfigError(key+' must be true or false')
            if p.get('fit','stretch') not in ('stretch','contain','cover'): raise ConfigError('fit must be stretch, contain or cover')
            if p.get('filter','lanczos3') not in ('lanczos3','bicubic','bilinear'): raise ConfigError('unsupported scaling filter')
            video=p['video']
            for key in ('speed','reorder'):
                if key in video and type(video[key]) is not bool: raise ConfigError('video.'+key+' must be true or false')
            if 'gop' in video and (type(video['gop']) is not int or not 1<=video['gop']<=1000): raise ConfigError('gop must be an integer in 1..1000')
            for key in ('crop','rect'):
                if key in video:
                    value=video[key]
                    if not isinstance(value,list) or len(value)!=4 or any(type(v) not in (float,int) for v in value) or min(value[:2])<0 or min(value[2:])<=0: raise ConfigError(key+' must be [x,y,positive width,positive height]')
            for kind in ('loudness','text','anomalies'):
                if type(p[kind]['enabled']) is not bool: raise ConfigError(kind+'.enabled must be true or false')
            if p['loudness']['enabled'] and p['audio']['codec']=='none': raise ConfigError('audio QC requires an audio output')
            for key in ('tolerance','max_silence','max_clipped_samples','max_channel_difference'):
                if key in p['loudness']: positive(p['loudness'][key],key,True)
            for key in ('target','true_peak','silence_threshold'):
                if key in p['loudness'] and (type(p['loudness'][key]) not in (int,float) or not -100<=p['loudness'][key]<=0): raise ConfigError(key+' must be between -100 and 0 dB')
            text=p['text']
            for key in ('size','minimum_size','minimum_contrast','max_error'):
                if key in text: positive(text[key],key)
            if 'box' in text:
                box=text['box']
                if not isinstance(box,list) or len(box)!=4 or any(type(v) not in (int,float) or not 0<=v<=1 for v in box) or box[2]<=0 or box[3]<=0 or box[0]+box[2]>1 or box[1]+box[3]>1: raise ConfigError('text box must be normalized [x,y,width,height] inside the image')
            for key in ('safe_area','minimum_edge_recall'):
                if key in text and (type(text[key]) not in (int,float) or not 0<=text[key]<=1): raise ConfigError(key+' must be in 0..1')
            if text.get('enabled') and not text.get('font'): raise ConfigError('enabled text QC requires an explicit font file')
            for key in ('black_min','freeze_min','noise'):
                if key in p['anomalies']: positive(p['anomalies'][key],key)
            if p['anomalies'].get('policy','fail') not in ('fail','report'): raise ConfigError('anomalies policy must be fail or report')
            for key in ('allow_black','allow_freeze'):
                value=p['anomalies'].get(key,[])
                if not isinstance(value,list) or any(not isinstance(v,list) or len(v)!=2 or any(type(x) not in (float,int) for x in v) or v[0]<0 or v[1]<=v[0] for v in value): raise ConfigError(key+' must contain [start_seconds,end_seconds] intervals')
            quality=p['quality']
            if quality.get('minimum_bitrate',500000)>quality.get('maximum_bitrate',video.get('bitrate',8000000)): raise ConfigError('minimum_bitrate exceeds maximum_bitrate')
            for key,maximum in (('max_probes',12),('probe_frames',240)):
                if key in quality and (type(quality[key]) is not int or not 1<=quality[key]<=maximum): raise ConfigError(key+' must be a bounded positive integer')
            if 'sample_frames' in quality and (not isinstance(quality['sample_frames'],list) or not 1<=len(quality['sample_frames'])<=16): raise ConfigError('quality sample_frames needs 1..16 frames')
            for key,maximum in (('minimum_ssim',1),('minimum_vmaf',100)):
                if key in quality and (type(quality[key]) not in (int,float) or not 0<=quality[key]<=maximum): raise ConfigError(key+' is outside its metric range')
        for item in self.declarations['gate']:
            if not isinstance(item.get('pattern'),str) or not item['pattern'] or len(item['pattern'])>4096: raise ConfigError('gate pattern must be a nonempty bounded regex string')
            try: pattern=re.compile(item['pattern'],re.M)
            except re.error as error: raise ConfigError('invalid gate pattern: '+str(error)) from error
            if 'equal' in item and (not isinstance(item['equal'],list) or len(item['equal'])!=2 or any(type(v) is not int or v<1 or v>pattern.groups for v in item['equal'])): raise ConfigError('gate equal must name two existing capture groups')
        for item in self.declarations['publish']:
            if not isinstance(item.get('root'),str): raise ConfigError('publish root is required')
            if item.get('layout','flat') not in ('flat','profiles'): raise ConfigError('publish layout must be flat or profiles')
            if set(item.get('profiles',profiles))-set(profiles): raise ConfigError('publish references an unknown profile')
            if not isinstance(item.get('files',[]),list) or any(not isinstance(v,str) for v in item.get('files',[])): raise ConfigError('publish files must be a string array')

    def resources(self):
        result={}
        for item in self.declarations['resources']: result.update({k:v for k,v in item.items() if k!='name'})
        for key,value in result.items():
            if key not in ('cache_days',): positive(value,'resources.'+key,allow_zero=key in ('disk_reserve_mb','retries'))
        for key in ('jobs','animation_jobs','decode_ahead','segments_ahead','retries','native_timeout_ms'):
            if key in result and type(result[key]) is not int: raise ConfigError(key+' must be an integer')
        if 'cache_days' in result: positive(result['cache_days'],'cache_days')
        if result.get('segments_ahead',3) not in (1,2,3): raise ConfigError('segments_ahead must be 1, 2 or 3')
        if not 1<=result.get('decode_ahead',6)<=32: raise ConfigError('decode_ahead must be in 1..32')
        if not 0<=result.get('retries',2)<=5: raise ConfigError('retries must be in 0..5')
        return result

    def associated(self,kind,profile):
        return [item for item in self.declarations[kind] if item.get('profile','all') in ('all',profile)]
