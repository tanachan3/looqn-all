import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

class StaticWebViewPage extends StatefulWidget {
  final String url;
  final String? title;

  const StaticWebViewPage({super.key, required this.url, this.title});

  @override
  State<StaticWebViewPage> createState() => _StaticWebViewPageState();
}

class _StaticWebViewPageState extends State<StaticWebViewPage> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) async {
            // 今後 tel: などの外部スキームにも対応する場合はここで分岐を追加する
            if (request.url.startsWith('mailto:')) {
              final uri = Uri.parse(request.url);

              try {
                final didLaunch = await launchUrl(
                  uri,
                  mode: LaunchMode.externalApplication,
                );

                if (!didLaunch) {
                  // 端末にメールアプリが無いなどで起動できなかった場合のフォールバック
                  debugPrint('メールアプリを起動できませんでした: $uri');
                  // TODO: 必要に応じてダイアログ表示などのユーザー通知も検討する
                }
              } catch (error, stackTrace) {
                debugPrint('メールアプリ起動時に例外が発生しました: $error');
                debugPrint('$stackTrace');
              }

              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
        ),
      );

    // キャッシュクリア
    _controller.clearCache();

    _controller.loadRequest(
      Uri.parse(widget.url),
      headers: {'Cache-Control': 'no-cache'},
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title ?? 'Info',
          style: const TextStyle(color: Colors.black),
        ),
        backgroundColor: Colors.white, // ← 背景色を白に
        iconTheme: const IconThemeData(color: Colors.black), // ← 戻るボタンも黒
        elevation: 0.5, // 薄い下線。不要なら0
      ),
      backgroundColor: Colors.white, // 本体も白
      body: WebViewWidget(controller: _controller),
    );
  }
}
