import 'package:flutter/material.dart';
import 'package:geomsg_chat/map.dart';
//import 'package:geomsg_chat/chat_page.dart';
import 'package:geomsg_chat/my_page.dart';

class CommonBottomNavigationBar extends StatelessWidget {
  final int currentIndex;

  // ★ 追加：MapPage に渡すために保持
  final bool locationPermissionGranted;

  const CommonBottomNavigationBar({
    Key? key,
    required this.currentIndex,
    required this.locationPermissionGranted, // ★ 追加
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.map),
          label: 'マップ',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.chat),
          label: 'チャット',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person),
          label: 'マイページ',
        ),
      ],
      currentIndex: currentIndex,
      onTap: (index) {
        if (index == currentIndex) {
          return;
        }

        if (index == 0) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => MapPage(
                locationPermissionGranted: locationPermissionGranted,
              ),
            ),
          );
        } else if (index == 1) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              // ※ いまは MapPage のまま（後で ChatPage に差し替え）
              builder: (context) => MapPage(
                locationPermissionGranted: locationPermissionGranted,
              ),
            ),
          );
        } else if (index == 2) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => MyPage()),
          );
        }
      },
    );
  }
}
