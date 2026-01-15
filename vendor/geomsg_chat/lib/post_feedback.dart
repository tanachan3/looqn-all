import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class PostFeedbackPage extends StatefulWidget {
  const PostFeedbackPage({Key? key}) : super(key: key);

  @override
  State<PostFeedbackPage> createState() => _PostFeedbackPageState();
}

class _PostFeedbackPageState extends State<PostFeedbackPage> {
  final TextEditingController _controller = TextEditingController();
  bool _submitted = false;
  bool _loading = false;

  Future<void> _submitFeedback() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _controller.text.trim().isEmpty) return;

    setState(() => _loading = true);

    await FirebaseFirestore.instance.collection('feedbacks').add({
      'message': _controller.text.trim(),
      'user_id': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });

    setState(() {
      _submitted = true;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;

    if (_submitted) {
      return Scaffold(
        backgroundColor: Colors.white, // 追加
        appBar: AppBar(
          backgroundColor: Colors.white, // 追加
          iconTheme: const IconThemeData(color: Colors.black), // 戻るボタン黒
          title: Text(
            loc.feedbackTitle,
            style: const TextStyle(color: Colors.black), // タイトル黒
          ),
          elevation: 0,
        ),
        body: Center(child: Text(loc.feedbackThankYou)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white, // 追加
      appBar: AppBar(
        backgroundColor: Colors.white, // 追加
        iconTheme: const IconThemeData(color: Colors.black), // 戻るボタン黒
        title: Text(
          loc.feedbackTitle,
          style: const TextStyle(color: Colors.black), // タイトル黒
        ),
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(loc.feedbackPrompt),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              maxLines: 6,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: loc.feedbackHint,
                filled: true, // 追加（オプション）
                fillColor: Colors.white, // 追加（オプション）
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            _loading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _controller.text.trim().isEmpty || _loading
                        ? null
                        : _submitFeedback,
                    child: Text(loc.feedbackSend),
                  ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
