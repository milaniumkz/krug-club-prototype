/* Handle our notification clicks before Firebase's default listener. A click
 * must also open the inbox when a tab already exists, not merely focus it. */
self.addEventListener('notificationclick', event => {
  const id = event.notification.data?.FCM_MSG?.data?.notification_id;
  if (!/^[a-f0-9-]{36}$/.test(id || '')) return;
  event.stopImmediatePropagation();
  event.notification.close();
  const target = new URL('/?notification=' + encodeURIComponent(id), self.location.origin);
  event.waitUntil((async () => {
    const windows = await self.clients.matchAll({type: 'window', includeUncontrolled: true});
    for (const client of windows) {
      if (new URL(client.url).origin !== self.location.origin) continue;
      try {
        const navigated = await client.navigate(target.href);
        if (navigated) return await navigated.focus();
      } catch (_) { /* A closing tab can no longer navigate. */ }
    }
    return self.clients.openWindow(target.href);
  })());
});
/* Same-origin public configuration only; FCM displays each background payload. */
importScripts('/api/push-config.js');
if (self.QM_FIREBASE_CONFIG?.enabled) {
  importScripts('/firebase/firebase-app-compat.js');
  importScripts('/firebase/firebase-messaging-compat.js');
  firebase.initializeApp(self.QM_FIREBASE_CONFIG.options);
  firebase.messaging();
}
