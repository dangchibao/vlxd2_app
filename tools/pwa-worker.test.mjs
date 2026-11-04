import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
import {test} from 'node:test';
import assert from 'node:assert/strict';
const source=await readFile(new URL('../web/offline-worker.js',import.meta.url),'utf8');
test('Offline worker intercepts static app assets, never Auth, store APIs or writes',async()=>{
 const handlers={};
 vm.runInNewContext(source,{URL,Request,importScripts(){},BAYHAI_CACHE:'bayhai-static-test',BAYHAI_ASSETS:['index.html','sqlite3.wasm'],
  self:{registration:{scope:'https://bayhai.example/'},location:{origin:'https://bayhai.example'},addEventListener:(name,handler)=>handlers[name]=handler},
  caches:{open:async()=>({match:async()=>new Response('cached')})},Response,fetch:async()=>new Response('network'),
 });
 for(const [url,method] of [['https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword','POST'],['https://firestore.googleapis.com/v1/stores','GET'],['https://bayhai.example/stores/shop/users','GET'],['https://bayhai.example/index.html','POST']]) {
  let intercepted=false; handlers.fetch({request:{url,method,mode:'cors'},respondWith(){intercepted=true;}}); assert.equal(intercepted,false,url);
 }
 let pending; handlers.fetch({request:{url:'https://bayhai.example/sqlite3.wasm',method:'GET',mode:'cors'},respondWith(value){pending=value;}});
 assert.equal(await (await pending).text(),'cached');
});
