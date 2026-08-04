// firebase-messaging-sw.js
// ────────────────────────────────────────────────────
// Required by Firebase Cloud Messaging on Flutter Web —
// without this exact file at the web root, FCM fails with
// "unsupported MIME type ('text/html')" because the browser
// falls back to serving index.html for the missing script.
//
// Uses the Firebase "compat" JS SDK (via CDN, not npm) since
// service workers can't use Dart/Flutter code directly — this
// is Google's own documented approach for Flutter Web + FCM.
//
// Config values match frontend/lib/firebase_options.dart
// (web section) exactly — if that ever changes, update here too.

importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyAf3sUkn8kD1uOEI7HZW4penaq8zJHpSTU',
  appId: '1:148309638140:web:39367d1ef7a7a77b0cd079',
  messagingSenderId: '148309638140',
  projectId: 'fasterapp-ec0a5',
  authDomain: 'fasterapp-ec0a5.firebaseapp.com',
  storageBucket: 'fasterapp-ec0a5.firebasestorage.app',
});

const messaging = firebase.messaging();

// Handles a push that arrives while the tab is closed/backgrounded.
// Foreground messages (tab open) are handled in Dart instead —
// see PushNotificationService.initialize()'s FirebaseMessaging
// .onMessage listener.
messaging.onBackgroundMessage((payload) => {
  console.log('[firebase-messaging-sw.js] Background message:', payload);

  const notificationTitle = payload.notification?.title || 'Faster App';
  const notificationOptions = {
    body: payload.notification?.body || '',
    icon: '/icons/Icon-192.png',
    data: payload.data,
  };

  self.registration.showNotification(notificationTitle, notificationOptions);
});