import 'package:firebase_core/firebase_core.dart';

import 'firebase_options_dev.dart' as dev_options;
import 'firebase_options_prod.dart' as prod_options;

/// アプリのビルドフレーバーを表現します。
enum AppFlavor { dev, prod }

const String _flavorName = String.fromEnvironment('FLAVOR', defaultValue: 'prod');

AppFlavor? _runtimeFlavorOverride;

/// アプリ実行中に利用するフレーバーを上書きします。
void setRuntimeAppFlavor(AppFlavor flavor) {
  _runtimeFlavorOverride = flavor;
}

/// 現在のビルドで利用するフレーバー。
AppFlavor get currentAppFlavor {
  final override = _runtimeFlavorOverride;
  if (override != null) {
    return override;
  }
  return _flavorName == 'dev' ? AppFlavor.dev : AppFlavor.prod;
}

extension AppFlavorName on AppFlavor {
  String get name => switch (this) {
        AppFlavor.dev => 'dev',
        AppFlavor.prod => 'prod',
      };
}

/// 指定したフレーバーに対応する [FirebaseOptions] を返します。
FirebaseOptions firebaseOptionsFor(AppFlavor flavor) {
  switch (flavor) {
    case AppFlavor.dev:
      return dev_options.DefaultFirebaseOptions.currentPlatform;
    case AppFlavor.prod:
      return prod_options.DefaultFirebaseOptions.currentPlatform;
  }
}

/// 既存コードとの互換性を維持するためのラッパークラス。
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform =>
      firebaseOptionsFor(currentAppFlavor);
}
