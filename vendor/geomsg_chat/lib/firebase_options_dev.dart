// FlutterFire CLIで生成される開発環境用の設定ファイルです。
// 実際の値は `flutterfire configure --project=LooQN-dev --out=lib/firebase_options_dev.dart` を実行して上書きしてください。
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DevFirebaseOptions have not been configured for web. '
        'FlutterFire CLIを使って再設定してください。',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DevFirebaseOptions have not been configured for this platform. '
          'FlutterFire CLIを使って再設定してください。',
        );
      default:
        throw UnsupportedError(
          'このプラットフォーム向けのDevFirebaseOptionsは未対応です。',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCzA0CFE8oN8YUNsJz3i2RkqrUJoA7_ms8',
    appId: '1:860475896267:android:041318d8e71349c3cc064e',
    messagingSenderId: '860475896267',
    projectId: 'looqn-dev',
    storageBucket: 'looqn-dev.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCk0epZonjgC_k1-Cfze84xkxiEzBXTEkI',
    appId: '1:860475896267:ios:a94e6dcbd80968dccc064e',
    messagingSenderId: '860475896267',
    projectId: 'looqn-dev',
    storageBucket: 'looqn-dev.firebasestorage.app',
    iosBundleId: 'net.looqn.app.dev',
  );
}
