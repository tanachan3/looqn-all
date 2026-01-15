import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geomsg_chat/post.dart';
import 'package:geomsg_chat/marker_icon_generator.dart';
import 'package:geomsg_chat/read_status_db.dart';

class MapMarkerService {
  /// 投稿一覧からマーカーを逐次生成して返すストリーム
  Stream<Marker> streamMarkersFromPosts({
    required List<Post> posts,
    required Map<String, int> commentCounts,
    required Function(Post) onMarkerTap,
  }) async* {
    final userId = FirebaseAuth.instance.currentUser?.uid;

    for (final post in posts) {
      if (post.position == null) continue;

      // 事前計算されたコメント数を使用
      final commentCount = commentCounts[post.id] ?? 0;

      // 既読状態を確認
      bool isRead = false;
      if (userId != null) {
        final parentIsRead = await ReadStatusDb.instance.isRead(post.id);
        final hasUnreadComment =
            await ReadStatusDb.instance.hasUnreadComments(post.id);

        // 投稿・コメントとも既読なら既読扱い
        isRead = parentIsRead && !hasUnreadComment;
      }

      // アイコン生成（バッジ有無・透過対応）
      BitmapDescriptor icon;
      if (commentCount > 0) {
        icon = await MarkerIconGenerator.createMarkerWithCommentCount(
          commentCount: commentCount,
          opacity: isRead ? 0.3 : 1.0,
        );
      } else {
        icon = await MarkerIconGenerator.createMarkerWithoutComment(
          opacity: isRead ? 0.3 : 1.0,
        );
      }

      yield Marker(
        markerId: MarkerId(post.id),
        position: LatLng(post.position!.latitude, post.position!.longitude),
        icon: icon,
        onTap: () => onMarkerTap(post),
        zIndex: isRead ? 0 : 1,
      );
    }
  }

  Future<Set<Marker>> createMarkersFromPosts({
    required List<Post> posts,
    required Map<String, int> commentCounts,
    required Function(Post) onMarkerTap,
  }) async {
    final Set<Marker> markers = {};
    await for (final marker in streamMarkersFromPosts(
      posts: posts,
      commentCounts: commentCounts,
      onMarkerTap: onMarkerTap,
    )) {
      markers.add(marker);
    }

    return markers;
  }
}
