import {readdir,readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import path from 'node:path';
const root = path.resolve('build/web');
const files=[];
async function walk(dir) {
  for (const entry of await readdir(dir,{withFileTypes:true})) {
    const full=path.join(dir,entry.name);
    if(entry.isDirectory()) await walk(full);
    else {
      const relative=path.relative(root,full).replaceAll('\\','/');
      if(!relative.endsWith('.map') && !['offline-assets.js','offline-worker.js','flutter_service_worker.js'].includes(relative)) files.push(relative);
    }
  }
}
await walk(root); files.sort();
if(!files.includes('index.html') || !files.includes('main.dart.js')) throw Error('Run flutter build web first.');
const digest=createHash('sha256');
for(const file of files) { digest.update(file); digest.update(await readFile(path.join(root,file))); }
await writeFile(path.join(root,'offline-assets.js'),`const BAYHAI_CACHE = ${JSON.stringify('bayhai-static-'+digest.digest('hex').slice(0,20))};\nconst BAYHAI_ASSETS = ${JSON.stringify(files)};\n`);
console.log(`PWA offline manifest prepared: ${files.length} local assets.`);
