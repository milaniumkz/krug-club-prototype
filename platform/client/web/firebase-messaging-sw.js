/* Same-origin public configuration only. FCM handles notification display/click. */
importScripts('/api/push-config.js');
if (self.QM_FIREBASE_CONFIG?.enabled) {
  importScripts('/firebase/firebase-app-compat.js');
  importScripts('/firebase/firebase-messaging-compat.js');
  firebase.initializeApp(self.QM_FIREBASE_CONFIG.options);
  firebase.messaging();
}
