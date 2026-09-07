import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform, debugPrint;
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../firebase_options.dart';
import '../models/progress_backup.dart';
import 'graffiti_firebase_service.dart';

class ProgressSyncCancelled implements Exception {
  const ProgressSyncCancelled();
}

class ProgressSyncException implements Exception {
  final String message;
  const ProgressSyncException(this.message);

  @override
  String toString() => message;
}

/// Google Sign-In + RTDB backup under `irodoku_progress/{uid}`.
class ProgressSyncService {
  ProgressSyncService._();

  static const progressPath = 'irodoku_progress';
  static const _cloudTimeout = Duration(seconds: 25);

  static Future<void> _gate = Future.value();
  static GoogleSignIn? _googleSignIn;

  static bool get googleSignInSupported {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  /// Prompts Google Sign-In if needed. On web this must run from a click.
  static Future<String> ensureSignedIn() => _ensureGoogleLinkedUid();

  /// Firebase + anonymous auth so Continue can open the Google popup immediately.
  static Future<void> warmUp() async {
    await GraffitiFirebaseService.ensureInitialized();
  }

  static Future<void> save(ProgressBackup backup) {
    return _exclusive(() async {
      final uid = await _ensureGoogleLinkedUid();
      final payload = jsonEncode(backup.toJson());
      await _withTimeout(
        GraffitiFirebaseService.database.ref('$progressPath/$uid').set({
          'v': ProgressBackup.schemaVersion,
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
          'json': payload,
        }),
        'saving',
      );
    });
  }

  static Future<ProgressBackup?> load() {
    return _exclusive(() async {
      final uid = await _ensureGoogleLinkedUid();
      final snap = await _withTimeout(
        GraffitiFirebaseService.database.ref('$progressPath/$uid').get(),
        'loading',
      );
      return parseCloudSnapshot(snap.value);
    });
  }

  /// Parses the RTDB node `{ v, updatedAt, json }`.
  static ProgressBackup? parseCloudSnapshot(Object? value) {
    if (value == null) return null;
    if (value is! Map) {
      throw const ProgressSyncException('Cloud backup is corrupted.');
    }
    final data = Map<Object?, Object?>.from(value);
    final raw = data['json'];
    if (raw == null) return null;
    if (raw is! String || raw.isEmpty) {
      throw const ProgressSyncException('Cloud backup is corrupted.');
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const ProgressSyncException('Cloud backup is corrupted.');
      }
      return ProgressBackup.fromJson(_asStringKeyMap(decoded));
    } on ProgressSyncException {
      rethrow;
    } on FormatException catch (e) {
      final message = e.message.toLowerCase();
      if (message.contains('version')) {
        throw const ProgressSyncException(
          'This backup was made with a newer version of Irodoku.',
        );
      }
      throw const ProgressSyncException('Cloud backup is corrupted.');
    } catch (_) {
      throw const ProgressSyncException('Cloud backup is corrupted.');
    }
  }

  static Future<String> _ensureGoogleLinkedUid() async {
    if (!googleSignInSupported) {
      throw const ProgressSyncException(
        'Sync is available on Android, iOS, and web.',
      );
    }
    final ready = await GraffitiFirebaseService.ensureInitialized();
    if (!ready) {
      throw const ProgressSyncException('Could not connect to the cloud.');
    }
    final webClientId = DefaultFirebaseOptions.googleWebClientId;
    if (!kIsWeb && webClientId.isEmpty) {
      throw const ProgressSyncException(
        'Google Sign-In is not configured yet. Add the Web client ID in Firebase Console.',
      );
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user != null && _hasGoogleProvider(user)) {
      return user.uid;
    }

    if (kIsWeb) {
      return _signInWithGooglePopup();
    }

    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        return await _signInWithGoogleProvider();
      }
      return await _signInWithGooglePlugin(webClientId);
    } on ProgressSyncCancelled {
      rethrow;
    } on ProgressSyncException {
      rethrow;
    } on FirebaseAuthException catch (e) {
      throw _fromAuthException(e);
    } catch (e) {
      throw _fromGoogleSignInError(e);
    }
  }

  /// Same Firebase Google provider as web (`signInWithPopup`), not the
  /// `google_sign_in` plugin. That plugin always calls `requestServerAuthCode`,
  /// which fails on Play installs (ApiException 12500 / 13) even when web works.
  static Future<String> _signInWithGoogleProvider() async {
    final provider = GoogleAuthProvider();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && _hasGoogleProvider(user)) return user.uid;

    // Drop the Graffiti anonymous session first. Linking it to Google is
    // what web does via popup; on Android `linkWithProvider` is unreliable
    // and Sync must use the Google UID anyway.
    if (user != null && user.isAnonymous) {
      await FirebaseAuth.instance.signOut();
    }

    try {
      final result = await FirebaseAuth.instance.signInWithProvider(provider);
      return result.user?.uid ??
          (throw const ProgressSyncException('Google Sign-In failed.'));
    } on FirebaseAuthException catch (e) {
      throw _fromAuthException(e);
    }
  }

  static Future<String> _signInWithGooglePlugin(String webClientId) async {
    final googleSignIn = _googleSignIn ??= GoogleSignIn(
      serverClientId: webClientId,
      scopes: const ['email', 'profile'],
    );
    try {
      await googleSignIn.signOut();
    } catch (_) {}
    late final GoogleSignInAccount? googleUser;
    try {
      googleUser = await googleSignIn.signIn();
    } catch (e) {
      throw _fromGoogleSignInError(e);
    }
    if (googleUser == null) throw const ProgressSyncCancelled();
    final googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;
    if (idToken == null) {
      throw const ProgressSyncException(
        'Google Sign-In did not return a token.',
      );
    }
    final credential = GoogleAuthProvider.credential(
      idToken: idToken,
      accessToken: googleAuth.accessToken,
    );
    return _linkOrSignInWithCredential(credential);
  }

  static Future<String> _signInWithGooglePopup() async {
    final provider = GoogleAuthProvider();
    final user = FirebaseAuth.instance.currentUser;
    try {
      if (user == null) {
        final result = await FirebaseAuth.instance.signInWithPopup(provider);
        return result.user?.uid ??
            (throw const ProgressSyncException('Google Sign-In failed.'));
      }
      try {
        final linked = await user.linkWithPopup(provider);
        return linked.user?.uid ?? user.uid;
      } on FirebaseAuthException catch (e) {
        if (e.code == 'provider-already-linked') {
          return FirebaseAuth.instance.currentUser?.uid ?? user.uid;
        }
        if (_googleAccountAlreadyUsed(e)) {
          final result = await FirebaseAuth.instance.signInWithPopup(provider);
          return result.user?.uid ??
              (throw const ProgressSyncException('Google Sign-In failed.'));
        }
        throw _fromAuthException(e);
      }
    } on ProgressSyncException {
      rethrow;
    } on ProgressSyncCancelled {
      rethrow;
    } on FirebaseAuthException catch (e) {
      throw _fromAuthException(e);
    }
  }

  static Future<String> _linkOrSignInWithCredential(
    AuthCredential credential,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      final result =
          await FirebaseAuth.instance.signInWithCredential(credential);
      return result.user?.uid ??
          (throw const ProgressSyncException('Google Sign-In failed.'));
    }
    if (_hasGoogleProvider(user)) return user.uid;

    try {
      final linked = await user.linkWithCredential(credential);
      return linked.user?.uid ?? user.uid;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'provider-already-linked') {
        return FirebaseAuth.instance.currentUser?.uid ?? user.uid;
      }
      if (_googleAccountAlreadyUsed(e)) {
        final result =
            await FirebaseAuth.instance.signInWithCredential(credential);
        return result.user?.uid ??
            (throw const ProgressSyncException('Google Sign-In failed.'));
      }
      throw _fromAuthException(e);
    }
  }

  static bool _googleAccountAlreadyUsed(FirebaseAuthException e) =>
      e.code == 'credential-already-in-use' ||
      e.code == 'email-already-in-use' ||
      e.code == 'account-exists-with-different-credential';

  static Never _fromGoogleSignInError(Object e) {
    debugPrint('Google Sign-In failed: $e');
    final text = e.toString();
    final code = e is PlatformException ? e.code : '';
    final api = RegExp(r'ApiException:\s*(\d+)').firstMatch(text)?.group(1);
    if (code == 'sign_in_canceled' ||
        api == '12501' ||
        text.contains('sign_in_canceled')) {
      throw const ProgressSyncCancelled();
    }
    if (api == '10' ||
        api == '8' ||
        api == '13' ||
        api == '12500' ||
        text.contains('DEVELOPER_ERROR')) {
      throw ProgressSyncException(
        'Google Sign-In is not set up for this install (error $api). '
        'Add the Play app signing SHA-1 in Firebase.',
      );
    }
    if (api == '7' || text.contains('NETWORK_ERROR') || code == 'network_error') {
      throw const ProgressSyncException(
        'Could not reach Google. Check your connection and try again.',
      );
    }
    final detail = api ?? (code.isEmpty ? 'unknown' : code);
    throw ProgressSyncException('Google Sign-In failed ($detail).');
  }

  static Never _fromAuthException(FirebaseAuthException e) {
    debugPrint('Firebase Auth failed: ${e.code} ${e.message}');
    if (e.code == 'popup-closed-by-user' ||
        e.code == 'cancelled-popup-request' ||
        e.code == 'web-context-cancelled' ||
        e.code == 'canceled') {
      throw const ProgressSyncCancelled();
    }
    if (e.code == 'popup-blocked') {
      throw const ProgressSyncException(
        'Chrome blocked the Google sign-in popup. Allow popups for this site and try again.',
      );
    }
    if (e.code == 'network-request-failed') {
      throw const ProgressSyncException(
        'Could not reach Google. Check your connection and try again.',
      );
    }
    if (e.code == 'too-many-requests') {
      throw const ProgressSyncException(
        'Too many sign-in attempts. Wait a moment and try again.',
      );
    }
    if (e.code == 'invalid-credential' || e.code == 'user-disabled') {
      throw const ProgressSyncException(
        'Google Sign-In could not be completed. Try another account.',
      );
    }
    if (e.code == 'operation-not-allowed') {
      throw const ProgressSyncException(
        'Google Sign-In is disabled in Firebase Authentication.',
      );
    }
    throw ProgressSyncException('Google Sign-In failed (${e.code}).');
  }

  static ProgressSyncException _fromDatabaseException(FirebaseException e) {
    if (e.code == 'permission-denied') {
      return const ProgressSyncException(
        'Could not access cloud backup. Try signing in again.',
      );
    }
    return const ProgressSyncException(
      'Could not reach the cloud. Check your connection and try again.',
    );
  }

  static bool _hasGoogleProvider(User user) =>
      user.providerData.any((info) => info.providerId == 'google.com');

  static Map<String, dynamic> _asStringKeyMap(Map<dynamic, dynamic> map) => {
        for (final entry in map.entries) entry.key.toString(): entry.value,
      };

  static Future<T> _exclusive<T>(Future<T> Function() action) {
    final previous = _gate;
    final done = Completer<void>();
    _gate = done.future;
    return previous.catchError((_) {}).then((_) async {
      try {
        return await action();
      } on ProgressSyncCancelled {
        rethrow;
      } on ProgressSyncException {
        rethrow;
      } on FirebaseAuthException catch (e) {
        throw _fromAuthException(e);
      } on FirebaseException catch (e) {
        throw _fromDatabaseException(e);
      } on TimeoutException {
        throw const ProgressSyncException(
          'Timed out. Check your connection and try again.',
        );
      } catch (_) {
        throw const ProgressSyncException(
          'Sync failed. Check your connection and try again.',
        );
      }
    }).whenComplete(done.complete);
  }

  static Future<T> _withTimeout<T>(Future<T> future, String action) {
    return future.timeout(
      _cloudTimeout,
      onTimeout: () => throw ProgressSyncException(
        'Timed out while $action. Check your connection and try again.',
      ),
    );
  }
}
