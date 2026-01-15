import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:geomsg_chat/post_feedback.dart';
import 'package:geomsg_chat/static_webview_page.dart';
import 'package:geomsg_chat/main.dart';
import 'package:geomsg_chat/login_screen.dart';

class MyPage extends StatefulWidget {
  const MyPage({super.key});

  @override
  State<MyPage> createState() => _MyPageState();
}

class _MyPageState extends State<MyPage> {
  String? _deleteStatus;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _fetchDeleteStatus();
  }

  Future<void> _fetchDeleteStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _deleteStatus = null);
      return;
    }
    final doc = await FirebaseFirestore.instance
        .collection('account_delete_requests')
        .doc(user.uid)
        .get();
    setState(() {
      _deleteStatus = doc.exists ? doc['status'] as String? : null;
    });
  }

  Future<void> _handleAccountDeleteButton() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _loading = true);

    final docRef = FirebaseFirestore.instance
        .collection('account_delete_requests')
        .doc(user.uid);

    if (_deleteStatus == 'pending') {
      // 申請取り消し
      await docRef.update({
        'status': 'canceled',
        'canceledAt': FieldValue.serverTimestamp(),
      });
    } else {
      // 削除申請
      await docRef.set({
        'user_id': user.uid,
        'requestedAt': FieldValue.serverTimestamp(),
        'status': 'pending',
      });
    }
    await _fetchDeleteStatus();
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Center(child: Text(loc.notLoggedIn));
    }

    // 言語とURL生成
    String lang = Localizations.localeOf(context).languageCode;
    const supportedLangs = ['ja', 'en'];
    if (!supportedLangs.contains(lang)) lang = 'en';
    const String baseUrl = 'https://geomsg-4d728.web.app';

    final isPending = _deleteStatus == 'pending';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          loc.myPageTitle,
          style: const TextStyle(color: Colors.black),
        ),
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black),
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark.copyWith(
          statusBarColor: Colors.white,
          statusBarIconBrightness: Brightness.dark,
        ),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 16),
          // ヘルプ
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: Text(loc.help),
            tileColor: Colors.white,
            onTap: () {
              final url = '$baseUrl/$lang/help.html';
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => StaticWebViewPage(
                    url: url,
                    title: loc.help,
                  ),
                ),
              );
            },
          ),
          // 利用規約
          ListTile(
            leading: const Icon(Icons.policy_outlined),
            title: Text(loc.terms),
            tileColor: Colors.white,
            onTap: () {
              final url = '$baseUrl/$lang/terms.html';
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => StaticWebViewPage(
                    url: url,
                    title: loc.terms,
                  ),
                ),
              );
            },
          ),
          // プライバシーポリシー
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: Text(loc.privacyPolicy),
            tileColor: Colors.white,
            onTap: () {
              final url = '$baseUrl/$lang/privacy_policy.html';
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => StaticWebViewPage(
                    url: url,
                    title: loc.privacyPolicy,
                  ),
                ),
              );
            },
          ),
          // ご意見ボックス
          ListTile(
            leading: const Icon(Icons.feedback_outlined),
            title: Text(loc.feedbackTitle),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const PostFeedbackPage(),
                ),
              );
            },
          ),
          const Divider(
            height: 1,
            color: Color(0xFFE0E0E0),
          ),
          // ログアウト
          ListTile(
            leading: const Icon(Icons.logout),
            title: Text(loc.logout),
            tileColor: Colors.white,
            onTap: () async {
              await FirebaseAuth.instance.signOut();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(loc.loggedOut)),
              );
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
          ),
          // アカウント削除申請／取消
          ListTile(
            leading: const Icon(Icons.delete_forever),
            title: Text(
              isPending ? loc.accountDeleteCancel : loc.accountDelete,
              style: TextStyle(color: isPending ? Colors.red : null),
            ),
            tileColor: Colors.white,
            onTap: _loading
                ? null
                : () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(isPending
                            ? loc.accountDeleteCancelTitle
                            : loc.accountDeleteRequestTitle),
                        content: Text(isPending
                            ? loc.accountDeleteCancelConfirm
                            : loc.accountDeleteRequestConfirm),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: Text(loc.cancel),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: Text(isPending ? loc.confirm : loc.request),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await _handleAccountDeleteButton();
                    }
                  },
          ),
          if (isPending)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                loc.accountDeletePending,
                style: const TextStyle(color: Colors.red),
              ),
            ),
        ],
      ),
    );
  }
}
