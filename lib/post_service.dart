import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geomsg_chat/util.dart';
import 'package:geomsg_chat/post.dart';
import 'package:geomsg_chat/read_status_db.dart';
import 'package:cloud_functions/cloud_functions.dart'; // Cloud Functions 呼び出し用
import 'package:geoflutterfire2/geoflutterfire2.dart'; // 追加：geohash計算用
import 'package:geolocator/geolocator.dart'; // 距離計算用

class DuplicateSubmissionException implements Exception {
  const DuplicateSubmissionException();

  @override
  String toString() => 'DuplicateSubmissionException';
}

class PostService {
  final CollectionReference postsRef =
      FirebaseFirestore.instance.collection('posts');

  static const _chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  static final Random _random = Random();

  static String generateSubmissionKey() {
    final timestamp =
        DateTime.now().microsecondsSinceEpoch.toRadixString(36).padLeft(8, '0');
    final randomPart = List.generate(
      8,
      (_) => _chars[_random.nextInt(_chars.length)],
    ).join();
    return '$timestamp$randomPart';
  }

  Future<void> addPost({
    required String userId,
    required String text,
    required String posterName,
    required GeoPoint position,
    required String submissionKey,
    String? parent = null, // 親IDのデフォルトはnull
    String? address, // ← 追加
  }) async {
    final encryptedText = encryptionService.encrypt(text);
    final encryptedUserId = encryptionService.encryptWithFixedIv(userId);

    // geohash を計算
    final geo = GeoFlutterFire().point(
      latitude: position.latitude,
      longitude: position.longitude,
    );
    final geohash = geo.hash.substring(0, 6);

    final docRef = postsRef.doc(submissionKey);

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      if (snapshot.exists) {
        throw const DuplicateSubmissionException();
      }

      transaction.set(docRef, {
        'user_id': encryptedUserId,
        'text': encryptedText,
        'posterName': posterName,
        'createdAt': Timestamp.now(),
        'position': position,
        'geohash': geohash, // 追加
        'latitude': position.latitude,
        'longitude': position.longitude,
        'isDeleted': false, // ← これを追加！！
        if (address != null) 'address': address,
        // parent を常に保存 (nullの場合はnullを保存)
        'parent': parent,
        'submissionKey': submissionKey,
      });
    });
  }

  // 投稿を取得（全件）
  Stream<List<DocumentSnapshot>> getPostsNearby() {
    return postsRef.snapshots().map((snapshot) => snapshot.docs.toList());
  }

  // 既読チェック
  Stream<bool> postReadStatusStream(
    String postId,
    CollectionReference postsRef,
    String userId,
  ) {
    return postsRef
        .doc(postId)
        .collection('readStatus')
        .doc(userId)
        .snapshots()
        .map((snapshot) => snapshot.exists);
  }

  // 既読フラグをつける
  Future<void> markMessageAsRead(
    String messageId,
    CollectionReference postsRef,
    String userId,
  ) async {
    await postsRef
        .doc(messageId)
        .collection('readStatus')
        .doc(userId)
        .set({'read': true});
  }

  // ユーザーをブロック
  Future<void> blockUser(
    String blockedUserId,
    CollectionReference blocksRef,
    String userId,
  ) async {
    await blocksRef
        .doc(userId)
        .collection('blockedUsers')
        .doc(blockedUserId)
        .set({});
  }

  /// Cloud Functions 経由でAIメッセージを取得
  ///
  /// 返却されるJSON文字列をパースし、ネストしたリストやマップから
  /// 文字列だけを抽出する。パースに失敗した場合は空のリストを返す。
  Future<List<String>> fetchAiMessages({
    required int count,
    required GeoPoint position,
    String language = '日本語',
    dynamic mockData,
  }) async {
    // 数値保証 & 範囲チェック（必要なら）
    final lat = position.latitude.toDouble();
    final lng = position.longitude.toDouble();
    assert(lat.isFinite && lng.isFinite);
    assert(lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180);

    // ★ GeoPointを直接渡さず、数値のMapで送る
    final payload = {
      'count': count.clamp(1, 5),
      'language': language,
      'position': {
        'latitude': lat,
        'longitude': lng,
      },
      'debug': true,
    };

    final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('fetchAiMessages');

    try {
      final data = mockData ?? (await callable.call(payload)).data;

      // サーバは { messages: [String, ...] } を返す想定
      if (data is Map && data['messages'] is List) {
        return (data['messages'] as List).map((e) => '$e').toList();
      }

      // 稀に文字列化されて返ってきた場合の保険
      if (data is Map && data['messages'] is String) {
        try {
          final decoded = jsonDecode(data['messages'] as String);
          if (decoded is Map && decoded['messages'] is List) {
            return (decoded['messages'] as List).map((e) => '$e').toList();
          }
        } catch (_) {/* ignore */}
      }

      return <String>[];
    } on FirebaseFunctionsException {
      rethrow;
    } catch (_) {
      rethrow;
    }
  }

  Future<void> markPostAndCommentsAsRead({
    required String postId,
    required CollectionReference postsRef,
    required String userId,
  }) async {
    // 親投稿の既読フラグをFirestoreとローカルDBに保存
    final parentDoc = await postsRef.doc(postId).get();
    await postsRef
        .doc(postId)
        .collection('readStatus')
        .doc(userId)
        .set({'read': true});

    final parentCreatedAt = ((parentDoc.data()
                as Map<String, dynamic>?)?['createdAt'] as Timestamp?)
            ?.toDate() ??
        DateTime.now();

    await ReadStatusDb.instance.markAsRead(postId, parentCreatedAt);

    // コメント一覧を取得
    final commentsSnapshot =
        await postsRef.where('parent', isEqualTo: postId).get();

    for (final commentDoc in commentsSnapshot.docs) {
      await postsRef
          .doc(commentDoc.id)
          .collection('readStatus')
          .doc(userId)
          .set({'read': true});
      final commentCreatedAt = ((commentDoc.data()
                  as Map<String, dynamic>?)?['createdAt'] as Timestamp?)
              ?.toDate() ??
          DateTime.now();
      await ReadStatusDb.instance.markAsRead(commentDoc.id, commentCreatedAt);
    }
  }

  /// 指定座標の半径[radiusMeters]m以内に投稿が存在するかチェック
  Future<bool> hasNearbyPosts({
    required double latitude,
    required double longitude,
    double radiusMeters = 50,
  }) async {
    // 現在地のgeohash（6桁）を計算
    final geo =
        GeoFlutterFire().point(latitude: latitude, longitude: longitude);
    final geohash = geo.hash.substring(0, 6);

    // 同じgeohashに属する投稿を取得
    final snapshot = await postsRef
        .where('isDeleted', isEqualTo: false)
        .where('geohash', isEqualTo: geohash)
        .get();

    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final lat = (data['latitude'] as num?)?.toDouble();
      final lng = (data['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      final distance =
          Geolocator.distanceBetween(latitude, longitude, lat, lng);
      if (distance <= radiusMeters) {
        return true;
      }
    }

    return false;
  }
}
