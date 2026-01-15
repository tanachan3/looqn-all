import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart'; // intl パッケージをインポート

class BlockedUsersPage extends StatefulWidget {
  @override
  _BlockedUsersPageState createState() => _BlockedUsersPageState();
}

class _BlockedUsersPageState extends State<BlockedUsersPage> {
  final user = FirebaseAuth.instance.currentUser!;
  List<Map<String, dynamic>> blockedUsers = []; // ブロックしたユーザーの情報リスト

  @override
  void initState() {
    super.initState();
    _loadBlockedUsers();
  }

  Future<void> _loadBlockedUsers() async {
    try {
      final blocksQuery = await FirebaseFirestore.instance
          .collection('blocks')
          .where('blockerId', isEqualTo: user.uid)
          .get();

      List<Map<String, dynamic>> users = [];
      for (var doc in blocksQuery.docs) {
        final blockedUserId = doc['blockedUserId']; // ブロックされたユーザーの UID

        final userData = await FirebaseFirestore.instance
            .collection('users')
            .doc(blockedUserId)
            .get();

        if (userData.exists) {
          // ブロック日時をフォーマットする
          final blockedAt = (doc['blockedAt'] as Timestamp).toDate();
          final formattedBlockedAt = DateFormat('yyyy/MM/dd').format(blockedAt);

          users.add({
            'id': doc.id,
            'blockedAt': formattedBlockedAt, // フォーマットしたブロック日時
            'blockedUserId': blockedUserId,
            'displayName': userData['displayName'], // ユーザーの表示名
          });
        }
      }

      setState(() {
        blockedUsers = users;
      });
    } catch (e) {
      print('ブロックしたユーザーの取得に失敗しました: $e');
    }
  }

  Future<void> _unblockUser(String blockId) async {
    try {
      await FirebaseFirestore.instance
          .collection('blocks')
          .doc(blockId)
          .delete();
      setState(() {
        blockedUsers.removeWhere((user) => user['id'] == blockId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ブロックを解除しました')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ブロックの解除に失敗しました: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ブロックしたユーザー')),
      body: blockedUsers.isEmpty
          ? Center(child: Text('ブロックしたユーザーはいません。'))
          : ListView.builder(
              itemCount: blockedUsers.length,
              itemBuilder: (context, index) {
                final blockedUser = blockedUsers[index];
                return ListTile(
                  title: Text('表示名: ${blockedUser['displayName']}'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ユーザーID: ${blockedUser['blockedUserId']}'),
                      Text('ブロック日時: ${blockedUser['blockedAt']}'),
                    ],
                  ),
                  trailing: IconButton(
                    icon: Icon(Icons.delete),
                    onPressed: () {
                      _unblockUser(blockedUser['id']);
                    },
                  ),
                );
              },
            ),
    );
  }
}
