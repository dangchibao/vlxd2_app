/* Only immutable app assets are cached. Auth and store traffic stay network-only. */
importScripts('offline-assets.js');
const absoluteAssets = new Set(BAYHAI_ASSETS.map(path => new URL(path, self.registration.scope).href));
self.addEventListener('install', event => {
  event.waitUntil(caches.open(BAYHAI_CACHE).then(cache => cache.addAll([...absoluteAssets].map(url => new Request(url,{cache:'reload'})))));
});
self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    for (const name of await caches.keys()) {
      if (name.startsWith('bayhai-static-') && name !== BAYHAI_CACHE) await caches.delete(name);
    }
    await self.clients.claim();
  })());
});
self.addEventListener('message', event => {
  if (event.data === 'BAYHAI_APPLY_UPDATE') self.skipWaiting();
});
self.addEventListener('fetch', event => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;
  url.search = ''; url.hash = '';
  if (request.mode === 'navigate' && url.href.startsWith(self.registration.scope)) {
    event.respondWith((async () => {
      const cached = await caches.match(new URL('index.html', self.registration.scope).href, {cacheName:BAYHAI_CACHE});
      return cached || fetch(request);
    })());
  } else if (absoluteAssets.has(url.href)) {
    event.respondWith((async () => {
      const cache = await caches.open(BAYHAI_CACHE);
      return (await cache.match(url.href)) || fetch(request);
    })());
  }
});
