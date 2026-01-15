import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geomsg_chat/util.dart' show encryptionService;

class Post {
  final String id;
  final String userId;
  final String text;
  final String posterName;
  final Timestamp createdAt;
  final GeoPoint? position;
  final String? geohash; // GeoHash 文字列
  final String? parent;
  final bool isComment;
  final String? address;
  final Map<String, dynamic>? readStatus;

  // ★追加：緯度・経度のgetter
  double? get latitude => position?.latitude;
  double? get longitude => position?.longitude;

  Post({
    required this.id,
    required this.userId,
    required this.text,
    required this.posterName,
    required this.createdAt,
    required this.position,
    this.geohash,
    this.parent,
    this.isComment = false,
    this.address,
    this.readStatus,
  });

  factory Post.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    final encryptedText = data['text'] ?? '';
    String decryptedText;
    try {
      decryptedText = encryptionService.decrypt(encryptedText);
    } catch (e) {
      decryptedText = encryptedText;
    }

    final encryptedUserId = data['user_id'] ?? '';
    String decryptedUserId;
    try {
      decryptedUserId = encryptionService.decryptWithFixedIv(encryptedUserId);
    } catch (e) {
      decryptedUserId = encryptedUserId;
    }

    return Post(
      id: doc.id,
      userId: decryptedUserId,
      text: decryptedText,
      posterName: data['posterName'] ?? '名無し',
      createdAt: data['createdAt'],
      position: data['position'],
      geohash: data['geohash'],
      parent: data['parent'],
      isComment: data['parent'] != null,
      address: data['address'],
      readStatus: data['readStatus'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'user_id': userId,
      'text': encryptionService.encrypt(text),
      'posterName': posterName,
      'createdAt': createdAt,
      'position': position,
      if (geohash != null) 'geohash': geohash,
      'parent': parent,
      if (address != null) 'address': address,
    };
  }

  Post copyWithPosition(GeoPoint position) {
    return Post(
      id: id,
      userId: userId,
      text: text,
      posterName: posterName,
      createdAt: createdAt,
      position: position,
      geohash: geohash,
      parent: parent,
      isComment: isComment,
      address: address,
      readStatus: readStatus,
    );
  }
}
