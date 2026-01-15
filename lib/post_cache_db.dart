import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'post.dart';

/// 投稿データをローカルに保存するシングルトン
class PostCacheDb {
  PostCacheDb._internal();
  static final PostCacheDb instance = PostCacheDb._internal();

  Database? _db;

  /// DB初期化
  Future<void> init() async {
    if (_db != null) return;
    final dir = await getApplicationDocumentsDirectory();
    final path = join(dir.path, 'posts_cache.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
CREATE TABLE posts (
  id TEXT PRIMARY KEY,
  user_id TEXT,
  text TEXT,
  posterName TEXT,
  created_at INTEGER,
  latitude REAL,
  longitude REAL,
  parent TEXT,
  geohash TEXT,
  address TEXT,
  isDeleted INTEGER
)''');
      },
    );
  }

  /// 投稿を追加・更新
  Future<void> upsertPosts(List<Post> posts) async {
    final db = _db;
    if (db == null) return;
    final batch = db.batch();
    for (final p in posts) {
      final pos = p.position;
      int created;
      if (p.createdAt is Timestamp) {
        created = (p.createdAt as Timestamp).millisecondsSinceEpoch;
      } else {
        created = (p.createdAt as DateTime).millisecondsSinceEpoch;
      }
      batch.insert(
        'posts',
        {
          'id': p.id,
          'user_id': p.userId,
          'text': p.text,
          'posterName': p.posterName,
          'created_at': created,
          'latitude': pos?.latitude,
          'longitude': pos?.longitude,
          'parent': p.parent,
          'geohash': p.geohash,
          'address': p.address,
          'isDeleted': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// 指定IDの投稿を削除済みとしてマーク
  Future<void> markAsDeleted(String id) async {
    final db = _db;
    if (db == null) return;
    await db.update(
      'posts',
      {'isDeleted': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 指定範囲で存在しない投稿を削除済みとしてマーク
  Future<void> markMissingInBoundsAsDeleted(
    double southLat,
    double westLng,
    double northLat,
    double eastLng,
    Set<String> remoteIds,
  ) async {
    final db = _db;
    if (db == null) return;
    final rows = await db.query(
      'posts',
      columns: ['id'],
      where: 'latitude >= ? AND latitude <= ? AND longitude >= ? AND longitude <= ?',
      whereArgs: [southLat, northLat, westLng, eastLng],
    );
    final batch = db.batch();
    for (final row in rows) {
      final id = row['id'] as String;
      if (!remoteIds.contains(id)) {
        batch.update('posts', {'isDeleted': 1}, where: 'id = ?', whereArgs: [id]);
      }
    }
    await batch.commit(noResult: true);
  }

  /// 指定した親IDのコメントで存在しないものを削除済みとしてマーク
  Future<void> markMissingForParentAsDeleted(
    String parentId,
    Set<String> remoteIds,
  ) async {
    final db = _db;
    if (db == null) return;
    final rows = await db.query(
      'posts',
      columns: ['id'],
      where: 'parent = ?',
      whereArgs: [parentId],
    );
    final batch = db.batch();
    for (final row in rows) {
      final id = row['id'] as String;
      if (!remoteIds.contains(id)) {
        batch.update('posts', {'isDeleted': 1}, where: 'id = ?', whereArgs: [id]);
      }
    }
    await batch.commit(noResult: true);
  }

  /// 指定範囲の投稿を取得
  Future<List<Post>> getPostsInBounds(
    double southLat,
    double westLng,
    double northLat,
    double eastLng,
  ) async {
    final db = _db;
    if (db == null) return [];
    final rows = await db.query(
      'posts',
      where:
          'latitude >= ? AND latitude <= ? AND longitude >= ? AND longitude <= ? AND (isDeleted IS NULL OR isDeleted = 0)',
      whereArgs: [southLat, northLat, westLng, eastLng],
      orderBy: 'created_at DESC',
    );
    return rows.map((row) {
      final lat = row['latitude'] as double?;
      final lng = row['longitude'] as double?;
      GeoPoint? pos;
      if (lat != null && lng != null) {
        pos = GeoPoint(lat, lng);
      }
      final createdAt =
          Timestamp.fromMillisecondsSinceEpoch(row['created_at'] as int);
      return Post(
        id: row['id'] as String,
        userId: row['user_id'] as String? ?? '',
        text: row['text'] as String? ?? '',
        posterName: row['posterName'] as String? ?? '名無し',
        createdAt: createdAt,
        position: pos,
        geohash: row['geohash'] as String?,
        parent: row['parent'] as String?,
        isComment: row['parent'] != null,
        address: row['address'] as String?,
        readStatus: null,
      );
    }).toList();
  }

  /// 古いデータを削除
  Future<void> purgeOldEntries(Duration limit) async {
    final db = _db;
    if (db == null) return;
    final now = DateTime.now();
    // Firestoreと同期するため次の5分を基準に閾値を設定
    DateTime nextFive;
    if (now.minute < 5) {
      nextFive = DateTime(now.year, now.month, now.day, now.hour, 5);
    } else {
      nextFive = DateTime(now.year, now.month, now.day, now.hour + 1, 5);
    }
    final threshold = nextFive.subtract(limit).millisecondsSinceEpoch;
    await db.delete(
      'posts',
      where: 'created_at < ?',
      whereArgs: [threshold],
    );
  }
}
