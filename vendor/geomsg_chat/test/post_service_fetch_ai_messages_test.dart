import 'package:test/test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geomsg_chat/post_service.dart';

void main() {
  test('JSONに含まれるマップとリストを平坦化して文字列を取得する', () async {
    const jsonString =
        '{"choices": [{"delta": {"content": "こんにちは"}}, {"delta": {"content": ["世界", {"more": "テスト"}]}}]}';
    final service = PostService();
    final result = await service.fetchAiMessages(
      count: 1,
      position: const GeoPoint(0, 0),
      language: '日本語',
      mockData: {'messages': jsonString},
    );
    expect(result, ['こんにちは', '世界', 'テスト']);
  });
}
