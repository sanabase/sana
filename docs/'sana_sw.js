'use strict';

const APP_CACHE = 'sana-app-v4';

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

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(APP_CACHE).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== APP_CACHE).map((k) => caches.delete(k)))
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

  const id    = data.reminder_id || '';
  const lang  = data.reminder_language || 'en';
  const title = data.title || 'SANA Reminder';
  const body  = data.body  || 'You have a medication reminder.';
  const tag   = id
    ? `sana-${id}-${data.reminder_date || ''}-${data.reminder_time || ''}`
    : 'sana-reminder';

  const takenLabel = {
    en: 'Taken',
    ar: 'تم تناول الدواء',
    es: 'Tomado',
    fr: 'Pris',
    de: 'Eingenommen',
    tr: 'Alındı',
    hi: 'दवा ले ली',
    zh: '已服药',
  }[lang] || 'Taken';

  const options = {
    body: body,
    icon: data.reminder_photo
      ? `data:image/jpeg;base64,${data.reminder_photo}`
      : '/sana/icons/Icon-192.png',
    badge: '/sana/icons/Icon-192.png',
    tag: tag,
    renotify: true,
    requireInteraction: true,
    vibrate: [400, 200, 400, 200, 400],
    actions: [
      { action: 'taken', title: takenLabel, type: 'button' },
    ],
    data: {
      reminder_id: id,
      reminder_time: data.reminder_time || '',
      reminder_date: data.reminder_date || '',
    },
  };

  event.waitUntil(
    Promise.all([
      self.registration.showNotification(title, options),
      // Try to speak the reminder when the phone supports speech in the SW.
      (async () => {
        try {
          if ('speechSynthesis' in self) {
            const utterance = new SpeechSynthesisUtterance(body);
            utterance.lang = {
              en: 'en-US', ar: 'ar-SA', es: 'es-ES', fr: 'fr-FR',
              de: 'de-DE', tr: 'tr-TR', hi: 'hi-IN', zh: 'zh-CN',
            }[lang] || 'en-US';
            self.speechSynthesis.speak(utterance);
          }
        } catch (_) {}
      })(),
    ])
  );
});

self.addEventListener('notificationclick', (event) => {
  const action = event.action;
  const data = event.notification.data || {};
  const id = data.reminder_id || '';

  event.notification.close();

  if (action === 'taken') {
    event.waitUntil(
      (async () => {
        try {
          const clients = await self.clients.matchAll({
            type: 'window',
            includeUncontrolled: true,
          });
          for (const client of clients) {
            client.postMessage({
              type: 'sana-taken',
              reminder_id: id,
            });
          }
        } catch (_) {}
      })()
    );
    return;
  }

  const url = id ? `/sana/?reminder=${encodeURIComponent(id)}` : '/sana/';
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(async (clients) => {
      // If a SANA window is already open, only post a message to it.
      // Do NOT navigate. That prevents the doubled screen.
      for (const client of clients) {
        if ('focus' in client) {
          client.postMessage({
            type: 'sana-open-reminder',
            reminder_id: id,
          });
          return client.focus();
        }
      }
      // No window open: open one with the URL.
      return self.clients.openWindow(url);
    })
  );
});