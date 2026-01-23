// lib/ad_helper.dart
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';

/// 広告ユニットIDを一元管理
class AdHelper {
  /// `--dart-define=ENABLE_ADS=false` でビルドすると広告をまるごと無効化できる
  /// （ストア用スクリーンショット取得時などに利用）。
  static const bool enableAds =
      bool.fromEnvironment('ENABLE_ADS', defaultValue: true);

  // Android 本番のバナー広告ユニットID
  static const String _androidBannerProd =
      'ca-app-pub-5074664306906349/5387716445';

  // iOS は未取得ならテストIDのままでOK（取得後に差し替え）
  static const String _iosBannerProd =
      'ca-app-pub-5074664306906349/8808927642';

  // Google 提供のテストID
  static const String _androidBannerTest =
      'ca-app-pub-3940256099942544/6300978111';
  static const String _iosBannerTest = 'ca-app-pub-3940256099942544/2934735716';

  /// バナー用ユニットID
  static String get bannerUnitId {
    final bool useTestId = !kReleaseMode; // Debug/Profile では常にテストID
    if (Platform.isAndroid) {
      return useTestId ? _androidBannerTest : _androidBannerProd;
    } else if (Platform.isIOS) {
      return useTestId ? _iosBannerTest : _iosBannerProd;
    }
    return ''; // 他プラットフォームは未対応
  }
}
