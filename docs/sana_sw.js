'use strict';

const APP_CACHE = 'sana-app-v5';

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
  e.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys.filter((k) => k !== APP_CACHE).map((k) => caches.delete(k))
      )
    ).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  let url;
  try { url = new URL(req.url); } catch (_) { return; }
  if (url.origin.includes('supabase.co') || !isCacheable(url)) return;

  event.respondWith(
    caches.match(req).then((cached) => {
      if (cached) return cached;
      return fetch(req).then((response) => {
        if (response.ok) {
          const copy = response.clone();
          caches.open(APP_CACHE).then((cache) => cache.put(req, copy)).catch(() => {});
        }
        return response;
      }).catch(() => cached);
    })
  );
});

self.addEventListener('push', (event) => {
  let data = {};
  try {
    if (event.data) data = event.data.json();
  } catch (_) {
    try { data = { body: event.data ? event.data.text() : '' }; } catch (_) {}
  }

  const title = data.title || 'SANA Reminder';
  const body  = data.body  || 'You have a medication reminder.';
  const id    = data.reminder_id || '';
  const tag   = id
    ? `sana-${id}-${data.reminder_date || ''}-${data.reminder_time || ''}`
    : 'sana-reminder';

  event.waitUntil(
    self.registration.showNotification(title, {
      body: body,
      icon: '/sana/icons/Icon-192.png',
      badge: '/sana/icons/Icon-192.png',
      tag: tag,
      renotify: true,
      requireInteraction: true,
      vibrate: [400, 200, 400, 200, 400],
      data: {
        reminder_id: id,
        reminder_time: data.reminder_time || '',
        reminder_date: data.reminder_date || '',
      },
    })
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const data = event.notification.data || {};
  const id = data.reminder_id || '';
  const url = id ? `/sana/?reminder=${encodeURIComponent(id)}` : '/sana/';

  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clients) => {
      for (const client of clients) {
        if ('focus' in client) {
          client.navigate(url);
          return client.focus();
        }
      }
      return self.clients.openWindow(url);
    })
  );
});