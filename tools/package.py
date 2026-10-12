#!/usr/bin/env python3
"""Validate and package only the reviewed application payload. No network."""
import argparse,gzip,hashlib,io,json,re,stat,tarfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
APP_ID='dev.cartridge.vibeboy'
REPOSITORY='Strizzo/vibeboy-cartridge'
PERMISSIONS=['network', 'storage', 'ssh']
def validate(root=ROOT,tag=None):
 root=Path(root)
 manifest=json.loads((root/'cartridge.json').read_text())
 version=manifest.get('version','')
 if manifest.get('id')!=APP_ID or not re.fullmatch(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)',version):raise ValueError('Invalid identity or version')
 if tag is not None and tag!='v'+version:raise ValueError('Tag differs from app version')
 if manifest.get('min_runtime')!='0.7.0' or manifest.get('entry')!='main.lua' or manifest.get('icon')!='icon.png':raise ValueError('Invalid runtime, entry or icon')
 if manifest.get('permissions')!=PERMISSIONS:raise ValueError('Permissions differ from the reviewed app')
 names=json.loads((root/'package-files.json').read_text())
 if len(names)!=len(set(names)) or len(names)!=len({n.casefold() for n in names}):raise ValueError('Duplicate payload paths')
 payload={}
 for name in names:
  parts=name.split('/')
  if any(not re.fullmatch(r'[A-Za-z0-9_][A-Za-z0-9_.-]*',p) for p in parts):raise ValueError('Unsafe path')
  allowed=name in {'cartridge.json','icon.png','icon_focused.png'} or (name.endswith('.lua') and (len(parts)==1 or parts[0] in {'screens','lib'})) or (parts[0]=='assets' and Path(name).suffix in {'.png','.svg','.json'})
  if not allowed:raise ValueError('Unsupported or private payload file')
  path=root
  for part in parts:
   path=path/part
   if path.is_symlink():raise ValueError('Payload links are forbidden')
  info=path.stat()
  if not stat.S_ISREG(info.st_mode) or info.st_nlink!=1:raise ValueError('Expected a regular file')
  payload[name]=path.read_bytes()
 if not {'main.lua','cartridge.json','icon.png'}<=set(payload):raise ValueError('Missing required app files')
 if sum(map(len,payload.values()))>32*1024*1024:raise ValueError('App is too large')
 return manifest,payload

def build(output,tag,root=ROOT):
 manifest,payload=validate(root,tag)
 stream=io.BytesIO()
 with tarfile.open(fileobj=stream,mode='w',format=tarfile.USTAR_FORMAT) as tar:
  for name,data in sorted(payload.items()):
   info=tarfile.TarInfo(name);info.size=len(data);info.mode=0o644;info.uid=info.gid=info.mtime=0;info.uname=info.gname=''
   tar.addfile(info,io.BytesIO(data))
 compressed=io.BytesIO()
 with gzip.GzipFile(fileobj=compressed,filename='',mode='wb',mtime=0) as gz:gz.write(stream.getvalue())
 data=compressed.getvalue();name=APP_ID+'.tar.gz'
 metadata={'id':APP_ID,'version':manifest['version'],'url':'https://github.com/'+REPOSITORY+'/releases/download/'+tag+'/'+name,'sha256':hashlib.sha256(data).hexdigest(),'size':len(data),'min_runtime':manifest['min_runtime'],'permissions':manifest['permissions']}
 output=Path(output)
 if output.is_symlink() or output.resolve()==Path(root).resolve():raise ValueError('Unsafe output location')
 output.mkdir(parents=True,exist_ok=True)
 products={name:data,'release.json':(json.dumps(metadata,indent=2)+'\n').encode()}
 products['SHA256SUMS']=''.join(hashlib.sha256(content).hexdigest()+'  '+filename+'\n' for filename,content in products.items()).encode()
 for filename,content in products.items():
  dest=output/filename
  if dest.is_symlink():raise ValueError('Output links are forbidden')
  dest.write_bytes(content)
 return metadata
if __name__=='__main__':
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--check',action='store_true');parser.add_argument('--tag');parser.add_argument('--output',type=Path,default=ROOT/'dist');args=parser.parse_args()
 if args.check:validate(ROOT,args.tag);print('Application payload validated')
 else:
  if not args.tag:parser.error('--tag is required for packaging')
  print(json.dumps(build(args.output,args.tag)))
