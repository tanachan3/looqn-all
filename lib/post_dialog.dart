import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geomsg_chat/post.dart';
import 'package:geomsg_chat/post_service.dart';
import 'package:geomsg_chat/util.dart';
import 'package:intl/intl.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:geomsg_chat/post_cache_db.dart';

Future<void> showPostDialog(
    BuildContext context, Post post, Position? currentPosition,
    {bool enableReply = true,
    bool enforceDistanceLimit = true,
    VoidCallback? onPosted}) async {
  final postPosition = post.position;

  // 距離制限（enforceDistanceLimitがtrueの場合のみ）
  if (enforceDistanceLimit && currentPosition != null && postPosition != null) {
    final distance = Geolocator.distanceBetween(
      currentPosition.latitude,
      currentPosition.longitude,
      postPosition.latitude,
      postPosition.longitude,
    );
    if (distance > 50) {
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (context) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          backgroundColor: Colors.white,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)!
                          .distanceLimitTitle, // 短く！例："Out of circle"
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      AppLocalizations.of(context)!.distanceLimitBody,
                      style: TextStyle(fontSize: 16, color: Colors.black87),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 6, // すこし外へ
                right: 6,
                child: IconButton(
                  icon: Icon(Icons.close, size: 22, color: Colors.black54),
                  splashRadius: 18,
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: AppLocalizations.of(context)!.close,
                ),
              ),
            ],
          ),
        ),
      );

      return;
    }

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId != null) {
      final postsRef = FirebaseFirestore.instance.collection('posts');
      await PostService().markPostAndCommentsAsRead(
        postId: post.id,
        postsRef: postsRef,
        userId: userId,
      );
    }
  }

  final userId = FirebaseAuth.instance.currentUser?.uid;
  final userPositionGeo = currentPosition != null
      ? GeoPoint(currentPosition.latitude, currentPosition.longitude)
      : null;

  final time = DateFormat('HH:mm').format(post.createdAt.toDate());
  final comments = await fetchComments(post.id);
  final TextEditingController _controller = TextEditingController();
  bool isPosting = false; // 返信投稿中かどうか
  String replySubmissionKey = PostService.generateSubmissionKey();

  showDialog(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return Dialog(
            backgroundColor: Colors.white,
            insetPadding: EdgeInsets.zero,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
            child: FractionallySizedBox(
              widthFactor: 0.92,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 閉じるボタン
                    Align(
                      alignment: Alignment.topRight,
                      child: IconButton(
                        icon: Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                    // 投稿本文
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4.0),
                      child: Text(
                        post.text,
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w500,
                            height: 1.6),
                      ),
                    ),
                    // 時刻＋3点メニュー
                    Row(
                      children: [
                        Text(
                          time,
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        Spacer(),
                        PopupMenuButton<String>(
                          icon: Icon(Icons.more_horiz, color: Colors.grey[600]),
                          onSelected: (value) async {
                            if (value == 'report') {
                              if (userId != null) {
                                await reportContent(
                                  reportedByUserId: userId,
                                  reportedPostId: post.id,
                                  reason: 'ユーザーによる通報',
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text(
                                          AppLocalizations.of(context)!
                                              .reported)),
                                );
                              }
                            }
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'report',
                              child: Text(
                                AppLocalizations.of(context)!.report,
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    SizedBox(height: 15),
                    Divider(thickness: 1),
                    // コメントアイコン
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4.0),
                      child: Icon(
                        Icons.comment_outlined,
                        color: looqnBlue,
                        size: 22,
                      ),
                    ),
                    // コメントリスト
                    if (comments.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Center(
                          child: Text(
                            AppLocalizations.of(context)!.noComments,
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      )
                    else
                      ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: 260),
                        child: ListView.separated(
                          shrinkWrap: true,
                          physics: BouncingScrollPhysics(),
                          itemCount: comments.length,
                          separatorBuilder: (context, idx) =>
                              Divider(thickness: 0.5, height: 24),
                          itemBuilder: (context, idx) {
                            final comment = comments[idx];
                            final commentTime = DateFormat('HH:mm')
                                .format(comment.createdAt.toDate());
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  comment.text,
                                  style: const TextStyle(fontSize: 16),
                                ),
                                const SizedBox(height: 1),
                                Row(
                                  children: [
                                    Text(
                                      commentTime,
                                      style: const TextStyle(
                                          fontSize: 12, color: Colors.grey),
                                    ),
                                    Spacer(),
                                    PopupMenuButton<String>(
                                      icon: Icon(Icons.more_horiz,
                                          color: Colors.grey[600]),
                                      onSelected: (value) async {
                                        if (value == 'report') {
                                          if (userId != null) {
                                            await reportContent(
                                              reportedByUserId: userId,
                                              reportedPostId: post.id,
                                              commentId: comment.id,
                                              reason: 'ユーザーによる通報',
                                            );
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                  content: Text(
                                                      AppLocalizations.of(
                                                              context)!
                                                          .reported)),
                                            );
                                          }
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        PopupMenuItem(
                                          value: 'report',
                                          child: Text(
                                            AppLocalizations.of(context)!
                                                .report,
                                            style: TextStyle(color: Colors.red),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    SizedBox(height: 20),
                    // 返信入力フォーム
                    if (enableReply)
                      Container(
                        width: double.infinity,
                        padding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 16,
                              offset: Offset(0, 4),
                            ),
                          ],
                          border: Border.all(
                            color: looqnBlue,
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _controller,
                                decoration: InputDecoration(
                                  hintText:
                                      AppLocalizations.of(context)!.enterReply,
                                  border: InputBorder.none,
                                  hintStyle: TextStyle(
                                    color: Color(0xFF90A4AE),
                                    fontSize: 16,
                                  ),
                                ),
                                style: TextStyle(fontSize: 18),
                              ),
                            ),
                            GestureDetector(
                              onTap: isPosting
                                  ? null
                                  : () async {
                                      final text = _controller.text.trim();
                                      if (text.isNotEmpty &&
                                          userId != null &&
                                          userPositionGeo != null) {
                                        String address = 'address not found';
                                        try {
                                          final placemarks =
                                              await placemarkFromCoordinates(
                                            userPositionGeo.latitude,
                                            userPositionGeo.longitude,
                                          );
                                          if (placemarks.isNotEmpty) {
                                            final place = placemarks.first;
                                            address =
                                                '${place.subLocality}, ${place.locality}, ${place.administrativeArea}, ${place.country}';
                                          }
                                        } catch (_) {}
                                        setState(() {
                                          isPosting = true;
                                        });
                                        try {
                                          await PostService().addPost(
                                            userId: userId,
                                            text: text,
                                            posterName: '名無し',
                                            position: userPositionGeo,
                                            submissionKey: replySubmissionKey,
                                            parent: post.id,
                                            address: address,
                                          );
                                          replySubmissionKey =
                                              PostService.generateSubmissionKey();
                                          if (onPosted != null) onPosted();
                                          Navigator.of(context).pop();
                                        } on DuplicateSubmissionException {
                                          replySubmissionKey =
                                              PostService.generateSubmissionKey();
                                        } finally {
                                          setState(() {
                                            isPosting = false;
                                          });
                                        }
                                      }
                                    },
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: looqnBlue,
                                  shape: BoxShape.circle,
                                ),
                                child: isPosting
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.send,
                                        color: Colors.white,
                                        size: 22,
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

Future<List<Post>> fetchComments(String parentPostId) async {
  final snapshot = await FirebaseFirestore.instance
      .collection('posts')
      .where('parent', isEqualTo: parentPostId)
      .where('isDeleted', isEqualTo: false)
      .orderBy('createdAt', descending: false)
      .get();
  final comments = snapshot.docs.map((doc) => Post.fromFirestore(doc)).toList();
  // Firestoreに存在しないコメントをローカルDBで削除済みにする
  final remoteIds = comments.map((c) => c.id).toSet();
  await PostCacheDb.instance.markMissingForParentAsDeleted(
    parentPostId,
    remoteIds,
  );
  PostCacheDb.instance.upsertPosts(comments);
  return comments;
}

class ReplyInputField extends StatefulWidget {
  final void Function(String) onSend;
  const ReplyInputField({required this.onSend, super.key});

  @override
  State<ReplyInputField> createState() => _ReplyInputFieldState();
}

class _ReplyInputFieldState extends State<ReplyInputField> {
  final TextEditingController _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(top: 12),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: looqnBlue, width: 1.3),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              decoration: const InputDecoration(
                hintText: '返信を入力...',
                border: InputBorder.none,
              ),
              style: TextStyle(fontSize: 16),
            ),
          ),
          GestureDetector(
            onTap: () {
              final text = _controller.text.trim();
              if (text.isNotEmpty) {
                widget.onSend(text);
                _controller.clear();
              }
            },
            child: Container(
              width: 36,
              height: 36,
              margin: EdgeInsets.only(left: 6, right: 2),
              decoration: BoxDecoration(
                color: looqnBlue,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.send,
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
