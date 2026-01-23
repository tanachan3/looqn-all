import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:geomsg_chat/post.dart';

class PostTile extends StatelessWidget {
  final Post post;
  final void Function(String postId)? deletePost;
  final VoidCallback? onTap; // ← 追加

  const PostTile({
    Key? key,
    required this.post,
    this.deletePost,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap, // ← タップ対応
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: ListTile(
          title: Text(
            DateFormat('HH:mm').format(post.createdAt.toDate()),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (post.address != null)
                Text(
                  post.address!,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              const SizedBox(height: 4),
              Text(post.text),
            ],
          ),
          trailing: deletePost != null
              ? IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () {
                    deletePost!(post.id);
                  },
                )
              : null,
        ),
      ),
    );
  }
}
