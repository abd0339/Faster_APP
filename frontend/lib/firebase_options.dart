// File generated manually from Firebase Console config values —
// equivalent to what `flutterfire configure` would produce.
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: lines_longer_than_80_chars

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Usage:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for iOS — '
          'this project has not set up an iOS Firebase app yet. '
          'Add one in the Firebase Console (Project settings → '
          'General → Your apps → Add app → iOS) and add the '
          'resulting config here before building for iOS.',
        );
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macOS.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAf3sUkn8kD1uOEI7HZW4penaq8zJHpSTU',
    appId: '1:148309638140:web:39367d1ef7a7a77b0cd079',
    messagingSenderId: '148309638140',
    projectId: 'fasterapp-ec0a5',
    authDomain: 'fasterapp-ec0a5.firebaseapp.com',
    storageBucket: 'fasterapp-ec0a5.firebasestorage.app',
    measurementId: 'G-701HKYKT45',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAohVihMv2f7jDcnLC87SWZKNr2T9G6a-8',
    appId: '1:148309638140:android:bfa96ba05f1295750cd079',
    messagingSenderId: '148309638140',
    projectId: 'fasterapp-ec0a5',
    storageBucket: 'fasterapp-ec0a5.firebasestorage.app',
  );
}
