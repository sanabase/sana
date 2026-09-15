'use strict';

// SANA service worker — used only for Web Push notifications.
// It does NOT replace or interfere with any Flutter service worker,
// because none is registered in this project.

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));

// --- Web Push: show the medication notification ---
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

// --- Notification click: open SANA at ?reminder=<id> ---
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
