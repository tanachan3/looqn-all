import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MarkerIconGenerator {
  static Future<BitmapDescriptor> createMarkerWithoutComment({
    double opacity = 1.0,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = const Size(120, 120);

    final bubblePath = _buildSpeechBubblePath(size);

    final bubbleFillPaint = Paint()
      ..color = Colors.white.withOpacity(opacity)
      ..style = PaintingStyle.fill;

    final bubbleStrokePaint = Paint()
      ..color = Colors.grey.shade600.withOpacity(opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(bubblePath, bubbleFillPaint);
    canvas.drawPath(bubblePath, bubbleStrokePaint);

    return await _finishImage(recorder, size);
  }

  static Future<BitmapDescriptor> createMarkerWithCommentCount({
    required int commentCount,
    double opacity = 1.0,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = const Size(120, 120);

    final bubblePath = _buildSpeechBubblePath(size);

    final bubbleFillPaint = Paint()
      ..color = Colors.white.withOpacity(opacity)
      ..style = PaintingStyle.fill;

    final bubbleStrokePaint = Paint()
      ..color = Colors.grey.shade600.withOpacity(opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(bubblePath, bubbleFillPaint);
    canvas.drawPath(bubblePath, bubbleStrokePaint);

    // バッジ（赤丸）
    final badgeRadius = 20.0;
    final badgeOffset = Offset(size.width - badgeRadius - 8, 22);
    final badgePaint = Paint()..color = Colors.red.withOpacity(opacity);
    canvas.drawCircle(badgeOffset, badgeRadius, badgePaint);

    // コメント数（白文字）
    final textPainter = TextPainter(
      text: TextSpan(
        text: commentCount > 99 ? '99+' : '$commentCount',
        style: TextStyle(
          color: Colors.white.withOpacity(opacity),
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      badgeOffset - Offset(textPainter.width / 2, textPainter.height / 2),
    );

    return await _finishImage(recorder, size);
  }

  // 吹き出しパス（一筆書き風）
  static Path _buildSpeechBubblePath(Size size) {
    final Path path = Path();

    // 吹き出しのメイン部分のサイズと位置
    final double bubbleWidth = 80;
    final double bubbleHeight = 60;
    final double bubbleX = 20;
    final double bubbleY = 20;
    final double borderRadius = 20; // Radius.circular(40) の半分

    // しっぽのサイズと位置
    final double tailWidth = 20;
    final double tailHeight = 20;
    final Offset tailTip = Offset(40, 100); // 尻尾の先端

    // 吹き出しの上辺の左端から開始
    path.moveTo(bubbleX + borderRadius, bubbleY);

    // 上辺
    path.lineTo(bubbleX + bubbleWidth - borderRadius, bubbleY);

    // 右上角の丸み
    path.arcToPoint(
      Offset(bubbleX + bubbleWidth, bubbleY + borderRadius),
      radius: Radius.circular(borderRadius),
      clockwise: true,
    );

    // 右辺
    path.lineTo(bubbleX + bubbleWidth, bubbleY + bubbleHeight - borderRadius);

    // 右下角の丸み（ここで尻尾の根元と接続）
    path.arcToPoint(
      Offset(bubbleX + bubbleWidth - borderRadius, bubbleY + bubbleHeight),
      radius: Radius.circular(borderRadius),
      clockwise: true,
    );

    // ここから尻尾のパスを開始
    path.lineTo(tailTip.dx + tailWidth / 2, bubbleY + bubbleHeight); // 尻尾の右側の根元
    path.lineTo(tailTip.dx, tailTip.dy); // 尻尾の先端
    path.lineTo(tailTip.dx - tailWidth / 2, bubbleY + bubbleHeight); // 尻尾の左側の根元

    // 左下角の丸み
    path.arcToPoint(
      Offset(bubbleX, bubbleY + bubbleHeight - borderRadius),
      radius: Radius.circular(borderRadius),
      clockwise: true,
    );

    // 左辺
    path.lineTo(bubbleX, bubbleY + borderRadius);

    // 左上角の丸み
    path.arcToPoint(
      Offset(bubbleX + borderRadius, bubbleY),
      radius: Radius.circular(borderRadius),
      clockwise: true,
    );

    path.close(); // パスを閉じる

    return path;
  }

  // 出力処理共通化
  static Future<BitmapDescriptor> _finishImage(
    ui.PictureRecorder recorder,
    Size size,
  ) async {
    final picture = recorder.endRecording();
    final img = await picture.toImage(size.width.toInt(), size.height.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(byteData!.buffer.asUint8List());
  }
}
