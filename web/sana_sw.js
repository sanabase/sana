'use strict';

const APP_CACHE = 'sana-app-v1';

const CACHEABLE = [
  /\/sana\/main\.dart\.js$/,
  /\/sana\/flutter_bootstrap\.js$/,
  /\/sana\/flutter\.js$/,
  /\/sana\/manifest\.json$/,
  /\/sana\/favicon\.png$/,
  /\/sana\/icons\//,
  /\/sana\/canvaskit\//,
  /\/sana\/assets\//,
];

function isCacheable(url) {
  const u = url.pathname;
  if (u.includes('supabase.co')) return false;
  return CACHEABLE.some((rx) => rx.test(u));
}

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(APP_CACHE).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (e) => {
  e.waitUntil(self.clients.claim());
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  let url;
  try { url = new URL(req.url); } catch (_) { return; }
  if (url.origin.includes('supabase.co')) return;
  if (!isCacheable(url)) return;

  event.respondWith(
    caches.match(req).then((cached) => {
      if (cached) return cached;
      return fetch(req).then((resp) => {
        if (resp.ok) {
          const copy = resp.clone();
          caches.open(APP_CACHE).then((c) => c.put(req, copy)).catch(() => {});
        }
        return resp;
      }).catch(() => cached);
    })
  );
});

self.addEventListener('push', (event) => {
  let data = {};
  try { data = event.data ? event.data.json() : {}; } catch (_) {}
  const title = data.title || 'SANA Reminder';
  const body  = data.body  || '';
  const id    = data.reminder_id || '';
  event.waitUntil(self.registration.showNotification(title, {
    body,
    icon: 'icons/Icon-192.png',
    badge: 'icons/Icon-192.png',
    tag: id ? ('sana-' + id) : 'sana',
    renotify: true,
    data: { reminder_id: id },
  }));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const id = event.notification.data && event.notification.data.reminder_id;
  const url = id ? ('/sana/?reminder=' + encodeURIComponent(id)) : '/sana/';
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true })
      .then((list) => {
        for (const c of list) {
          if ('focus' in c) { c.navigate(url); return c.focus(); }
        }
        return self.clients.openWindow(url);
      })
  );
});