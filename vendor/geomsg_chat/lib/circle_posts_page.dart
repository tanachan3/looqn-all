import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:geomsg_chat/post.dart';
import 'package:geomsg_chat/post_dialog.dart';
import 'package:geomsg_chat/post_service.dart';
import 'package:geomsg_chat/util.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:geomsg_chat/read_status_db.dart';
import 'package:geomsg_chat/post_cache_db.dart';

class CirclePostsPage extends StatefulWidget {
  final Position? position;
  const CirclePostsPage({Key? key, this.position}) : super(key: key);

  @override
  State<CirclePostsPage> createState() => _CirclePostsPageState();
}

class _CirclePostsPageState extends State<CirclePostsPage> {
  final CollectionReference postsReference =
      FirebaseFirestore.instance.collection('posts');
  Stream<List<Post>>? postStream;
  final Map<String, bool> _unreadCache = {};
  final Map<String, int> _commentCountCache = {};

  @override
  void initState() {
    super.initState();
    if (widget.position != null) {
      postStream = _getCirclePosts(widget.position!);
    } else {
      postStream = Stream.value([]);
    }
  }

  Stream<List<Post>> _getCirclePosts(Position pos) {
    final double lat = pos.latitude;
    final double lng = pos.longitude;
    final double deltaLat = 50 / 111000;
    final double deltaLng = 50 / (111000 * cos(lat * pi / 180));

    final boundingHashes = GeohashUtil.getGeohashBox(
      lat - deltaLat,
      lng - deltaLng,
      lat + deltaLat,
      lng + deltaLng,
      6,
    ).take(10).toList();

      return postsReference
          .where('isDeleted', isEqualTo: false)
          .where('geohash', whereIn: boundingHashes)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((snapshot) {
        // 削除された投稿をローカルDBに反映
        for (final change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.removed) {
            PostCacheDb.instance.markAsDeleted(change.doc.id);
          }
        }
        final posts = snapshot.docs.map((doc) => Post.fromFirestore(doc)).where((post) {
          if (post.parent != null) return false;
          if (post.position == null) return false;
          final dist = Geolocator.distanceBetween(
            lat,
            lng,
            post.position!.latitude,
            post.position!.longitude,
          );
          return dist <= 50;
        }).toList();
      PostCacheDb.instance.upsertPosts(posts);
      return posts;
    });
  }

  Future<bool> _hasUnread(Post post, String userId) async {
    if (_unreadCache.containsKey(post.id)) {
      return _unreadCache[post.id]!;
    }
    final parentIsRead = await ReadStatusDb.instance.isRead(post.id);
    final commentSnapshot =
        await postsReference.where('parent', isEqualTo: post.id).get();
    bool hasUnreadComment = false;
    for (final comment in commentSnapshot.docs) {
      final read = await ReadStatusDb.instance.isRead(comment.id);
      if (!read) {
        hasUnreadComment = true;
        break;
      }
    }
    final hasUnread = !(parentIsRead && !hasUnreadComment);
    _unreadCache[post.id] = hasUnread;
    return hasUnread;
  }

  Future<int> _getCommentCount(String postId) async {
    if (_commentCountCache.containsKey(postId)) {
      return _commentCountCache[postId]!;
    }
    final snapshot =
        await postsReference.where('parent', isEqualTo: postId).get();
    final count = snapshot.docs.length;
    _commentCountCache[postId] = count;
    return count;
  }

  void _openPost(Post post) async {
    final viewerId = FirebaseAuth.instance.currentUser?.uid;
    Position? currentPos;
    try {
      currentPos = await Geolocator.getCurrentPosition();
    } catch (_) {}

    if (viewerId != null) {
      await PostService().markPostAndCommentsAsRead(
        postId: post.id,
        postsRef: postsReference,
        userId: viewerId,
      );
      _unreadCache[post.id] = false;
    }

    if (!mounted) return;
    await showPostDialog(
      context,
      post,
      currentPos,
      enableReply: true,
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final loc = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: Text(loc.circleMessages),
      ),
      body: postStream == null
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<List<Post>>(
              stream: postStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text('${loc.errorOccurred}: ${snapshot.error}'),
                  );
                }
                final posts = snapshot.data ?? [];

                if (posts.isEmpty) {
                  return Center(child: Text(loc.noPosts));
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 0),
                  itemCount: posts.length,
                  separatorBuilder: (context, idx) =>
                      const Divider(thickness: 1, height: 1),
                  itemBuilder: (context, index) {
                    final post = posts[index];
                    DateTime? dt;
                    if (post.createdAt is Timestamp) {
                      dt = (post.createdAt as Timestamp).toDate();
                    } else if (post.createdAt is DateTime) {
                      dt = post.createdAt as DateTime;
                    }
                    final time =
                        dt != null ? DateFormat('HH:mm').format(dt) : '--:--';

                    return FutureBuilder<bool>(
                      future: currentUserId == null
                          ? Future.value(false)
                          : _hasUnread(post, currentUserId),
                      builder: (context, snap) {
                        final hasUnread = snap.data ?? false;

                        return InkWell(
                          onTap: () => _openPost(post),
                          child: Container(
                            color: hasUnread ? Colors.white : Colors.grey[300],
                            padding: const EdgeInsets.symmetric(
                                vertical: 12, horizontal: 16),
                            child: Row(
                              children: [
                                Text(
                                  time,
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey[600]),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    post.text.length > 12
                                        ? '${post.text.substring(0, 12)}...'
                                        : post.text,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.normal,
                                      color: hasUnread
                                          ? Colors.black
                                          : Colors.grey[600],
                                    ),
                                  ),
                                ),
                                FutureBuilder<int>(
                                  future: _getCommentCount(post.id),
                                  builder: (context, snapshot) {
                                    final count = snapshot.data ?? 0;
                                    if (count > 0) {
                                      final display =
                                          count > 99 ? '99+' : '$count';
                                      return Container(
                                        margin: const EdgeInsets.only(
                                            left: 8, top: 2),
                                        child: Row(
                                          children: [
                                            Icon(Icons.chat_bubble_outline,
                                                size: 18, color: looqnBlue),
                                            const SizedBox(width: 4),
                                            Text(
                                              display,
                                              style: TextStyle(
                                                  fontSize: 14,
                                                  color: looqnBlue),
                                            ),
                                          ],
                                        ),
                                      );
                                    }
                                    return const SizedBox.shrink();
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
    );
  }
}
