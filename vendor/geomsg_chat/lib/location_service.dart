import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
// 位置情報をFirestoreに保存
Future<void> savePosition(Position position, String userId) async {
  await FirebaseFirestore.instance.collection('locations').doc(userId).set({
    'user_id': userId,
    'position': GeoPoint(position.latitude, position.longitude),
  });
}

Future<Position?> getPosition(DocumentSnapshot snapshot) async {
  try {
    final geo = snapshot['position'];
    if (geo is! GeoPoint) return null;
    Position position = Position(
      latitude: geo.latitude,
      longitude: geo.longitude,
      timestamp: DateTime.now(),
      accuracy: 0.0,
      altitude: 0.0,
      heading: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
      altitudeAccuracy: 0.0,
      headingAccuracy: 0.0,
    );

    return Future.value(position);
  } catch (e) {
    print('Failed to load position: $e');
    return null;
  }
}

Future<void> getCurrentLocation({
  required Function(Position) onSuccess,
  required Function(Exception) onError,
}) async {
  bool serviceEnabled;
  LocationPermission permission;

  serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    onError(Exception("Location services are disabled."));
    return;
  }

  permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      onError(Exception("Location permissions are denied."));
      return;
    }
  }

  if (permission == LocationPermission.deniedForever) {
    onError(Exception("Location permissions are permanently denied."));
    return;
  }

  if (permission == LocationPermission.always ||
      permission == LocationPermission.whileInUse) {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );
      onSuccess(position);
    } catch (e) {
      onError(Exception('Failed to get location: $e'));
    }
  } else {
    onError(Exception("Location permission not sufficient."));
  }
}

Future<void> getCurrentLocationAndSendToFirebase() async {
  await getCurrentLocation(
    onSuccess: (Position position) async {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .update({
          'location': GeoPoint(position.latitude, position.longitude),
        });
      }
      print("位置情報を送信しました: ${position.latitude}, ${position.longitude}");
    },
    onError: (Exception e) {
      print("位置情報の取得に失敗しました: $e");
    },
  );
}
