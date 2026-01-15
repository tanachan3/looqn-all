import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _showCatchphrase = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _checkFirstLogin();
  }

  Future<void> _checkFirstLogin() async {
    final prefs = await SharedPreferences.getInstance();
    // 初回ログインの場合のみキャッチコピーを表示
    bool firstLogin = !(prefs.getBool('has_logged_in_once') ?? false);
    setState(() {
      _showCatchphrase = firstLogin;
    });
  }

  Future<void> _setFirstLoginDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_logged_in_once', true);
  }

  Future<void> signInWithGoogle(BuildContext context) async {
    setState(() {
      _loading = true;
    });
    try {
      final result = await _trySignInWithGoogle();
      if (result == null) {
        // ユーザーがキャンセルした場合は何もしない
        return;
      }

      final userCredential = result.credential;
      final user = userCredential.user;
      if (user == null) {
        throw FirebaseAuthException(
          code: 'user-null',
          message: 'Google認証でユーザー情報を取得できませんでした。',
        );
      }

      final userDoc =
          FirebaseFirestore.instance.collection('users').doc(user.uid);
      final docSnapshot = await userDoc.get();

      if (!docSnapshot.exists) {
        await userDoc.set({
          'displayName': '名無し',
          'isNotificationEnabled': true,
          'location': null,
          'createdAt': Timestamp.now(),
        });
      }

      await FirebaseFirestore.instance.collection('user_login').add({
        'user_id': user.uid,
        'type': 'google',
        'login_id': result.googleAccountId,
      });

      await _saveFCMToken(user.uid);
      await _setFirstLoginDone();
      // 遷移はauthStateChanges()側で自動
    } on PlatformException catch (e, stack) {
      print('PlatformException during Google sign-in: $e\n$stack');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Google認証でプラットフォームエラーが発生しました (code: ${e.code})',
          ),
        ),
      );
    } on FirebaseAuthException catch (e, stack) {
      print('FirebaseAuthException during Google sign-in: $e\n$stack');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Google認証でFirebaseエラーが発生しました: ${e.message}'),
        ),
      );
    } catch (e, stack) {
      print('Unexpected error during Google sign-in: $e\n$stack');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Google認証で予期しないエラーが発生しました: $e'),
        ),
      );
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> signInWithApple(BuildContext context) async {
    setState(() {
      _loading = true;
    });

    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('WebではApple認証に対応していません'),
        ),
      );
      setState(() {
        _loading = false;
      });
      return;
    }

    try {
      // Apple認証はnonceの付与が推奨されているため自前で生成
      final rawNonce = _generateNonce();
      final nonce = _sha256ofString(rawNonce);

      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );

      final oauthCredential = OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        rawNonce: rawNonce,
      );

      final userCredential =
          await FirebaseAuth.instance.signInWithCredential(oauthCredential);
      final user = userCredential.user;

      if (user == null) {
        throw FirebaseAuthException(
          code: 'user-null',
          message: 'Apple認証でユーザー情報を取得できませんでした。',
        );
      }

      final userDoc =
          FirebaseFirestore.instance.collection('users').doc(user.uid);
      final docSnapshot = await userDoc.get();

      if (!docSnapshot.exists) {
        await userDoc.set({
          'displayName': _deriveAppleDisplayName(appleCredential),
          'isNotificationEnabled': true,
          'location': null,
          'createdAt': Timestamp.now(),
        });
      }

      await FirebaseFirestore.instance.collection('user_login').add({
        'user_id': user.uid,
        'type': 'apple',
        'login_id': appleCredential.userIdentifier?.isNotEmpty == true
            ? appleCredential.userIdentifier
            : user.uid,
      });

      await _saveFCMToken(user.uid);
      await _setFirstLoginDone();
      // 遷移はauthStateChanges()側で自動
    } on PlatformException catch (e, stack) {
      print('PlatformException during Apple sign-in: $e\n$stack');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Apple認証でプラットフォームエラーが発生しました (code: ${e.code})',
          ),
        ),
      );
    } on SignInWithAppleAuthorizationException catch (e, stack) {
      // Apple側のキャンセルはexception経由で通知される
      if (e.code == AuthorizationErrorCode.canceled) {
        setState(() {
          _loading = false;
        });
        return;
      }
      print('AuthorizationException during Apple sign-in: $e\n$stack');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Apple認証でエラーが発生しました: ${e.message}'),
        ),
      );
    } on FirebaseAuthException catch (e, stack) {
      print('FirebaseAuthException during Apple sign-in: $e\n$stack');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Apple認証でFirebaseエラーが発生しました: ${e.message}'),
        ),
      );
    } catch (e, stack) {
      print('Unexpected error during Apple sign-in: $e\n$stack');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Apple認証で予期しないエラーが発生しました: $e'),
        ),
      );
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  GoogleSignIn _createGoogleSignIn() {
    final firebaseApp = Firebase.app();
    String? clientId;
    String? serverClientId;

    if (!kIsWeb) {
      switch (defaultTargetPlatform) {
        case TargetPlatform.iOS:
        case TargetPlatform.macOS:
          clientId = firebaseApp.options.iosClientId;
          serverClientId = firebaseApp.options.androidClientId;
          break;
        case TargetPlatform.android:
          serverClientId = firebaseApp.options.androidClientId;
          break;
        default:
          break;
      }
    }

    return GoogleSignIn(
      scopes: const ['profile', 'email'],
      clientId: clientId,
      serverClientId: serverClientId,
    );
  }

  Future<_GoogleSignInResult?> _trySignInWithGoogle() async {
    final googleSignIn = _createGoogleSignIn();
    try {
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        return null;
      }
      final googleAuth = await googleUser.authentication;

      if (googleAuth.idToken == null || googleAuth.accessToken == null) {
        return await _fallbackSignInWithFirebaseProvider(googleUser.id);
      }

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);

      return _GoogleSignInResult(
        userCredential,
        _inferGoogleAccountId(userCredential, googleUser.id),
      );
    } on PlatformException catch (e) {
      if (e.code == GoogleSignIn.kSignInCanceledError) {
        return null;
      }
      if (_shouldFallbackToFirebaseProvider(e)) {
        return await _fallbackSignInWithFirebaseProvider();
      }
      rethrow;
    }
  }

  bool _shouldFallbackToFirebaseProvider(PlatformException exception) {
    if (exception.code == GoogleSignIn.kSignInCanceledError) {
      return false;
    }
    const recoverableCodes = {
      GoogleSignIn.kNetworkError,
      GoogleSignIn.kSignInFailedError,
    };
    return recoverableCodes.contains(exception.code);
  }

  Future<_GoogleSignInResult> _fallbackSignInWithFirebaseProvider(
      [String? candidateId]) async {
    final provider = GoogleAuthProvider()
      ..addScope('email')
      ..addScope('profile')
      ..setCustomParameters({'prompt': 'select_account'});
    try {
      final credential =
          await FirebaseAuth.instance.signInWithProvider(provider);
      return _GoogleSignInResult(
        credential,
        _inferGoogleAccountId(credential, candidateId),
      );
    } on UnimplementedError {
      rethrow;
    } on FirebaseAuthException {
      rethrow;
    }
  }

  String? _inferGoogleAccountId(UserCredential credential,
      [String? candidateId]) {
    if (candidateId != null && candidateId.isNotEmpty) {
      return candidateId;
    }
    final additionalInfo = credential.additionalUserInfo;
    final profile = additionalInfo?.profile;
    final dynamic id = profile?['id'] ?? profile?['sub'];
    return id is String && id.isNotEmpty ? id : credential.user?.uid;
  }

  String _deriveAppleDisplayName(AuthorizationCredentialAppleID credential) {
    final displayName = [credential.familyName, credential.givenName]
        .where((value) => value != null && value.isNotEmpty)
        .join(' ');
    if (displayName.isNotEmpty) {
      return displayName;
    }
    return credential.email ?? '名無し';
  }

  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)])
        .join();
  }

  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<void> _saveFCMToken(String userId) async {
    try {
      final messaging = FirebaseMessaging.instance;
      final token = await messaging.getToken();
      if (token != null) {
        await FirebaseFirestore.instance
            .collection('remote_notification_token')
            .add({
          'user_id': userId,
          'type': 'fcm',
          'token': token,
        });
      }
    } catch (e) {
      print('Error saving FCM token: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: const Color(0xFF2196F3),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/splash_logo.png',
                width: 180,
                height: 180,
              ),
              const SizedBox(height: 30),
              if (_showCatchphrase)
                Text(
                  loc.loginCatchphrase,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                    shadows: [
                      Shadow(
                        blurRadius: 4,
                        color: Colors.black26,
                        offset: Offset(1, 1),
                      )
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
              if (_showCatchphrase) const SizedBox(height: 50),
              if (!_showCatchphrase) const SizedBox(height: 80),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                  minimumSize: const Size(260, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  elevation: 5,
                  side: const BorderSide(color: Color(0xFFE0E0E0)),
                ),
                onPressed: _loading
                    ? null
                    : () async {
                        await signInWithGoogle(context);
                      },
                child: _loading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SvgPicture.asset(
                            'assets/google_icon.svg',
                            width: 24,
                            height: 24,
                          ),
                          const SizedBox(width: 14),
                          Text(
                            loc.signInWithGoogle,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(260, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  elevation: 5,
                ),
                onPressed: _loading
                    ? null
                    : () async {
                        await signInWithApple(context);
                      },
                child: _loading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.apple,
                            size: 24,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 14),
                          Text(
                            loc.signInWithApple,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoogleSignInResult {
  const _GoogleSignInResult(this.credential, this.googleAccountId);

  final UserCredential credential;
  final String? googleAccountId;
}
