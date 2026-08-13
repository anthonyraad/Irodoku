import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Firebase options for Graffiti multiplayer (shared word-multiplayer project).
///
/// The web API key is baked in (normal for Firebase client apps). Restrict it in
/// Google Cloud (HTTP referrers / Android apps) and rely on Auth + RTDB rules.
/// Optional override: `--dart-define=FIREBASE_API_KEY=...`
class DefaultFirebaseOptions {
  static const String _apiKey = String.fromEnvironment(
    'FIREBASE_API_KEY',
    defaultValue: 'AIzaSyCdRvBtNt6JVbEmqJmCfdZD0a-zUIXHICs',
  );

  static bool get hasApiKey => _apiKey.isNotEmpty;

  static void _requireApiKey() {
    if (_apiKey.isEmpty) {
      throw StateError(
        'Missing FIREBASE_API_KEY. For local runs use:\n'
        '  flutter run --dart-define=FIREBASE_API_KEY=<key>',
      );
    }
  }

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported on this platform.',
        );
    }
  }

  static FirebaseOptions get web {
    _requireApiKey();
    return FirebaseOptions(
      apiKey: _apiKey,
      appId: '1:529750390715:web:ac93e397a70a331a35f69e',
      messagingSenderId: '529750390715',
      projectId: 'word-multiplayer',
      authDomain: 'word-multiplayer.firebaseapp.com',
      databaseURL: 'https://word-multiplayer-default-rtdb.firebaseio.com',
      storageBucket: 'word-multiplayer.firebasestorage.app',
      measurementId: 'G-3MG3NHQMT5',
    );
  }

  static FirebaseOptions get android {
    _requireApiKey();
    return FirebaseOptions(
      apiKey: _apiKey,
      appId: '1:529750390715:android:b1be26564294091635f69e',
      messagingSenderId: '529750390715',
      projectId: 'word-multiplayer',
      databaseURL: 'https://word-multiplayer-default-rtdb.firebaseio.com',
      storageBucket: 'word-multiplayer.firebasestorage.app',
    );
  }

  static FirebaseOptions get ios {
    _requireApiKey();
    return FirebaseOptions(
      apiKey: _apiKey,
      appId: '1:763109943495:web:893100513b9c5ef1f9f6e2',
      messagingSenderId: '763109943495',
      projectId: 'word-multiplayer',
      databaseURL: 'https://word-multiplayer-default-rtdb.firebaseio.com',
      storageBucket: 'word-multiplayer.firebasestorage.app',
    );
  }

  static FirebaseOptions get macos {
    _requireApiKey();
    return FirebaseOptions(
      apiKey: _apiKey,
      appId: '1:763109943495:web:893100513b9c5ef1f9f6e2',
      messagingSenderId: '763109943495',
      projectId: 'word-multiplayer',
      databaseURL: 'https://word-multiplayer-default-rtdb.firebaseio.com',
      storageBucket: 'word-multiplayer.firebasestorage.app',
    );
  }

  static FirebaseOptions get windows {
    _requireApiKey();
    return FirebaseOptions(
      apiKey: _apiKey,
      appId: '1:763109943495:web:893100513b9c5ef1f9f6e2',
      messagingSenderId: '763109943495',
      projectId: 'word-multiplayer',
      databaseURL: 'https://word-multiplayer-default-rtdb.firebaseio.com',
      storageBucket: 'word-multiplayer.firebasestorage.app',
    );
  }
}
