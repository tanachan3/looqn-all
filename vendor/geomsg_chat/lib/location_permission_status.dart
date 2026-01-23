import 'package:geolocator/geolocator.dart';

/// 位置情報の認可状態を表すエラー種別
enum LocationPermissionErrorType {
  /// 位置情報サービス自体が無効
  serviceDisabled,

  /// 位置情報の利用を拒否
  denied,

  /// 永続的に拒否（再リクエスト不可）
  deniedForever,
}

/// 位置情報の認可状態
class LocationPermissionStatus {
  const LocationPermissionStatus._({
    required this.granted,
    this.errorType,
  });

  /// 認可済み
  const LocationPermissionStatus.granted()
      : this._(granted: true, errorType: null);

  /// 認可失敗
  const LocationPermissionStatus.denied(this.errorType)
      : granted = false;

  /// 認可が取れているか
  final bool granted;

  /// 認可失敗時の詳細
  final LocationPermissionErrorType? errorType;
}

/// 位置情報の認可を確認・要求する
Future<LocationPermissionStatus> requestLocationPermission() async {
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    return const LocationPermissionStatus.denied(
      LocationPermissionErrorType.serviceDisabled,
    );
  }

  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }

  if (permission == LocationPermission.denied) {
    return const LocationPermissionStatus.denied(
      LocationPermissionErrorType.denied,
    );
  }

  if (permission == LocationPermission.deniedForever) {
    return const LocationPermissionStatus.denied(
      LocationPermissionErrorType.deniedForever,
    );
  }

  if (permission == LocationPermission.unableToDetermine) {
    return const LocationPermissionStatus.denied(
      LocationPermissionErrorType.denied,
    );
  }

  return const LocationPermissionStatus.granted();
}
