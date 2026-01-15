import 'package:encrypt/encrypt.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' as material;
import 'package:geohash_plus/geohash_plus.dart';

final encryptionService = EncryptionService('your-secret-passphrase');
const material.Color looqnBlue = material.Color(0xFF2196F3);

class EncryptionService {
  final Key key;

  EncryptionService(String passphrase)
      : key = Key.fromUtf8(sha256
            .convert(utf8.encode(passphrase))
            .toString()
            .substring(0, 32));

  // 通常の暗号化（IVをランダムに生成して先頭に結合）
  String encrypt(String data) {
    final iv = IV.fromLength(16);
    final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
    final encrypted = encrypter.encrypt(data, iv: iv);
    final combined = iv.bytes + encrypted.bytes;
    return base64UrlEncode(combined);
  }

  // 通常の復号化（先頭16バイトをIVとして使う）
  String decrypt(String encryptedData) {
    final decoded = base64Url.decode(encryptedData);
    final iv = IV(Uint8List.fromList(decoded.sublist(0, 16)));
    final encryptedBytes = decoded.sublist(16);
    final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
    return encrypter.decrypt(Encrypted(encryptedBytes), iv: iv);
  }

  // 固定IVを使った暗号化（user_idなど検索に使う用）
  String encryptWithFixedIv(String data) {
    final fixedIv = IV.fromUtf8('16charsfixediv!!'); // 16文字固定
    final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
    final encrypted = encrypter.encrypt(data, iv: fixedIv);
    return base64UrlEncode(encrypted.bytes);
  }

  // 固定IVを使った復号化
  String decryptWithFixedIv(String encryptedData) {
    final fixedIv = IV.fromUtf8('16charsfixediv!!');
    final encryptedBytes = base64Url.decode(encryptedData);
    final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
    return encrypter.decrypt(Encrypted(encryptedBytes), iv: fixedIv);
  }
}

// 通報データをFirestoreに保存
Future<void> reportContent({
  required String reportedByUserId,
  required String reportedPostId,
  String? commentId,
  required String reason, // 今回は仮で"ユーザーによる通報"などを入れる
}) async {
  await FirebaseFirestore.instance.collection('reports').add({
    'reportedBy': reportedByUserId,
    'reportedPostId': reportedPostId,
    if (commentId != null) 'reportedCommentId': commentId,
    'reason': reason,
    'timestamp': FieldValue.serverTimestamp(),
  });
}

class GeohashUtil {
  static String encode(double latitude, double longitude, {int precision = 5}) {
    return GeoHash.encode(latitude, longitude, precision: precision).hash;
  }

  static List<String> getGeohashBox(
    double southLat,
    double westLng,
    double northLat,
    double eastLng,
    int precision,
  ) {
    final geohashes = <String>{};
    final latStep = (northLat - southLat) / 8;
    final lngStep = (eastLng - westLng) / 8;
    for (double lat = southLat; lat <= northLat; lat += latStep) {
      for (double lng = westLng; lng <= eastLng; lng += lngStep) {
        geohashes.add(GeoHash.encode(lat, lng, precision: precision).hash);
      }
    }
    return geohashes.toList();
  }
}
