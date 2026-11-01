from pathlib import Path
import hashlib,json
root=Path(__file__).resolve().parents[1]/'build/web'
files=sorted(p.relative_to(root).as_posix() for p in root.rglob('*') if p.is_file() and p.name not in ['sw.js','flutter_service_worker.js'])
version=hashlib.sha256(b''.join((root/f).read_bytes() for f in files)).hexdigest()[:16]
script='''const CACHE='flait-offline-__VERSION__';
const FILES=__FILES__;
const paths=new Set(FILES.map(p=>new URL(p,self.registration.scope).href));
self.addEventListener('install',event=>event.waitUntil((async()=>{
 const cache=await caches.open(CACHE);
 for(const path of FILES){
   const response=await fetch(new Request(path,{cache:'reload',credentials:'same-origin'}));
   if(!response.ok||response.redirected)throw new Error('Could not cache app asset');
   const content=response.headers.get('content-type')||'';
   if(path.endsWith('.js')&&content.includes('text/html'))throw new Error('Sign in before installing offline');
   await cache.put(path,response);
 }
 self.skipWaiting();
})()));
self.addEventListener('activate',event=>event.waitUntil((async()=>{
 for(const key of await caches.keys()){if(key.startsWith('flait-offline-')&&key!==CACHE)await caches.delete(key);}
 await self.clients.claim();
})()));
self.addEventListener('fetch',event=>{
 if(event.request.method!=='GET')return;
 const url=new URL(event.request.url);
 if(url.origin!==self.location.origin)return;
 const isHome=event.request.mode==='navigate'&&url.pathname===new URL(self.registration.scope).pathname;
 if(!isHome&&!paths.has(url.href))return;
 event.respondWith((async()=>{
   const cache=await caches.open(CACHE);
   if(isHome){try {const response=await fetch(event.request);if(response.ok)return response;}catch(_){} return (await cache.match('index.html'))||Response.error();}
   return (await cache.match(event.request))||fetch(event.request);
 })());
});
'''.replace('__VERSION__',version).replace('__FILES__',json.dumps(files))
(root/'sw.js').write_text(script)
print(f'Offline package: {len(files)} assets, cache {version}')
