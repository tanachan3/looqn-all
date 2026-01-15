import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:geomsg_chat/util.dart';
import 'package:geomsg_chat/post.dart';
import 'package:geomsg_chat/post_dialog.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:geomsg_chat/post_cache_db.dart';

class UserPostsPage extends StatefulWidget {
  final String userId;
  const UserPostsPage({required this.userId});
  @override
  _UserPostsPageState createState() => _UserPostsPageState();
}

class _UserPostsPageState extends State<UserPostsPage> {
  final postsReference = FirebaseFirestore.instance.collection('posts');
  final Map<String, int> _commentCountCache = {};

  Future<int> getCommentCount(String parentId) async {
    if (_commentCountCache.containsKey(parentId)) {
      return _commentCountCache[parentId]!;
    }
    final snapshot = await postsReference
        .where('parent', isEqualTo: parentId)
        .where('isDeleted', isEqualTo: false)
        .get();

    final count = snapshot.docs.length;
    _commentCountCache[parentId] = count;
    return count;
  }

  Future<void> deletePost(String postId) async {
    final loc = AppLocalizations.of(context)!;
    try {
      await postsReference.doc(postId).update({'isDeleted': true});
      // ローカルDBにも削除を反映
      await PostCacheDb.instance.markAsDeleted(postId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.postDeleted)),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.postDeleteFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: Text(loc.myPosts),
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          bottom: TabBar(
            tabs: [
              Tab(text: loc.postsTab),
              Tab(text: loc.commentsTab),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _PostList(
              userId: widget.userId,
              showComments: false,
              deletePost: deletePost,
              getCommentCount: getCommentCount,
            ),
            _PostList(
              userId: widget.userId,
              showComments: true,
              deletePost: deletePost,
            ),
          ],
        ),
      ),
    );
  }
}

class _PostList extends StatelessWidget {
  final bool showComments;
  final String userId;
  final Future<void> Function(String postId) deletePost;
  final Future<int> Function(String postId)? getCommentCount;

  const _PostList({
    required this.showComments,
    required this.userId,
    required this.deletePost,
    this.getCommentCount,
  });

  Stream<List<Post>> _loadPosts() {
    final postsRef = FirebaseFirestore.instance.collection('posts');
    final encryptedUserId = encryptionService.encryptWithFixedIv(userId);

    Query query = postsRef
        .where('user_id', isEqualTo: encryptedUserId)
        .where('isDeleted', isEqualTo: false);

    // parentフィルターはFirestoreクエリには入れず、アプリ側でフィルタ
    return query.orderBy('createdAt', descending: true).snapshots().map((s) {
      // Firestoreから削除された投稿をローカルDBに反映
      for (final change in s.docChanges) {
        if (change.type == DocumentChangeType.removed) {
          PostCacheDb.instance.markAsDeleted(change.doc.id);
        }
      }
      final posts = s.docs.map(Post.fromFirestore).toList();
      final filtered = showComments
          ? posts.where((p) => p.parent != null).toList()
          : posts.where((p) => p.parent == null).toList();
      PostCacheDb.instance.upsertPosts(filtered);
      return filtered;
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;

    return StreamBuilder<List<Post>>(
      stream: _loadPosts(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('エラーが発生しました'));
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final posts = snapshot.data!;
        if (posts.isEmpty) {
          return Center(
            child: Text(
              showComments ? loc.noComments : loc.noPosts,
            ),
          );
        }

        return ListView.separated(
          padding: EdgeInsets.zero,
          itemCount: posts.length,
          separatorBuilder: (_, __) => const Divider(thickness: 1, height: 1),
          itemBuilder: (context, index) {
            final post = posts[index];
            final parentId = post.parent ?? post.id;
            return InkWell(
              onTap: () async {
                final parentSnapshot = await FirebaseFirestore.instance
                    .collection('posts')
                    .doc(parentId)
                    .get();
                if (!parentSnapshot.exists) return;
                final parentPost = Post.fromFirestore(parentSnapshot);

                Position? currentPosition;
                try {
                  currentPosition = await Geolocator.getCurrentPosition();
                } catch (_) {
                  currentPosition = null;
                }

                showPostDialog(
                  context,
                  parentPost,
                  currentPosition,
                  enableReply: false,
                  enforceDistanceLimit: false,
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                child: Row(
                  children: [
                    Text(
                      DateFormat('HH:mm').format(post.createdAt.toDate()),
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (post.address != null)
                            Text(
                              post.address!,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          Text(
                            post.text.length > 12
                                ? '${post.text.substring(0, 12)}...'
                                : post.text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                    if (!showComments && getCommentCount != null)
                      FutureBuilder<int>(
                        future: getCommentCount!(post.id),
                        builder: (context, snapshot) {
                          final count = snapshot.data ?? 0;
                          if (count > 0) {
                            final display = count > 99 ? '99+' : '$count';
                            return Container(
                              margin: const EdgeInsets.only(left: 8, top: 2),
                              child: Row(
                                children: [
                                  Icon(Icons.chat_bubble_outline,
                                      size: 18, color: looqnBlue),
                                  const SizedBox(width: 4),
                                  Text(
                                    display,
                                    style:
                                        TextStyle(fontSize: 14, color: looqnBlue),
                                  ),
                                ],
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => deletePost(post.id),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
