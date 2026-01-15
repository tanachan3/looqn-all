import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// 投稿既読状態をローカルDBで管理するシングルトンクラス
class ReadStatusDb {
  ReadStatusDb._internal();
  static final ReadStatusDb instance = ReadStatusDb._internal();

  Database? _db;

  /// DBを初期化
  Future<void> init() async {
    if (_db != null) return;
    final dir = await getApplicationDocumentsDirectory();
    final path = join(dir.path, 'read_status.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
CREATE TABLE read_status (
  message_id TEXT PRIMARY KEY,
  created_at INTEGER,
  read_at INTEGER
)''');
      },
    );
  }

  /// 既読登録（メッセージIDと作成時刻を保存）
  Future<void> markAsRead(String id, DateTime createdAt) async {
    final db = _db;
    if (db == null) return;
    await db.insert(
      'read_status',
      {
        'message_id': id,
        'created_at': createdAt.millisecondsSinceEpoch,
        'read_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 既読かどうかを判定
  Future<bool> isRead(String id) async {
    final db = _db;
    if (db == null) return false;
    final result = await db.query(
      'read_status',
      columns: ['message_id'],
      where: 'message_id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  /// 指定した投稿に未読コメントがあるかどうか判定
  Future<bool> hasUnreadComments(String parentId) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('posts')
        .where('parent', isEqualTo: parentId)
        .get();

    for (final doc in snapshot.docs) {
      final read = await isRead(doc.id);
      if (!read) return true;
    }
    return false;
  }

  /// 指定期間より古いレコードを削除
  Future<void> purgeOldEntries(Duration limit) async {
    final db = _db;
    if (db == null) return;
    final now = DateTime.now();
    // Firestoreのパージ時間に一致させるため次の5分を設定
    DateTime nextFive;
    if (now.minute < 5) {
      nextFive = DateTime(now.year, now.month, now.day, now.hour, 5);
    } else {
      nextFive = DateTime(now.year, now.month, now.day, now.hour + 1, 5);
    }
    final threshold = nextFive.subtract(limit).millisecondsSinceEpoch;
    await db.delete(
      'read_status',
      where: 'created_at < ?',
      whereArgs: [threshold],
    );
  }
}
