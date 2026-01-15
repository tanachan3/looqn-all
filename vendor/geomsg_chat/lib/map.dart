import 'dart:math';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart'; // Cloud Functions を使うため
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geoflutterfire2/geoflutterfire2.dart';

import 'package:geomsg_chat/util.dart' hide GeohashUtil; // ← GeohashUtil を隠す
import 'package:geomsg_chat/geohash_util.dart' as gh; // ← gh 別名で使う
import 'package:geomsg_chat/post.dart';
import 'package:geomsg_chat/post_service.dart';
import 'package:geomsg_chat/map_marker_service.dart';
import 'package:geomsg_chat/post_dialog.dart';
import 'package:geomsg_chat/post_cache_db.dart';
import 'package:geomsg_chat/my_page.dart';
import 'package:geomsg_chat/user_posts_page.dart';
import 'package:geomsg_chat/circle_posts_page.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:geomsg_chat/maintenance_page.dart';
import 'widgets/ad_banner.dart';

class MapPage extends StatefulWidget {
  const MapPage({
    super.key,
    required this.locationPermissionGranted,
  });

  final bool locationPermissionGranted;

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> with WidgetsBindingObserver {
  // ===== ダミーユーザー（テスト投稿用） =====
  static const String kDummyUserId = '10000';
  static const String kDummyPosterName = 'ダミーユーザー';

  GoogleMapController? mapController;
  static const LatLng _defaultLocation = LatLng(35.681236, 139.767125);

  // 投稿IDをキーにしたマーカー管理用Map（markerId.value = postId を想定）
  final Map<String, Marker> _markerMap = {};
  Set<Marker> get markers => _markerMap.values.toSet();

  final Set<Circle> circles = {};
  Position? currentPosition;
  bool isLoading = true;

  // 投稿処理中かどうかのフラグ
  bool _isPosting = false;
  final TextEditingController _textController = TextEditingController();
  String _mapStyle = '';
  String _submissionKey = PostService.generateSubmissionKey();

  Timer? _reloadTimer;

  // 複数回の同時取得を防ぐためのガード
  bool _fetchingPosts = false;
  bool _navigatedToMaintenance = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.locationPermissionGranted) {
      _getCurrentLocation();
    } else {
      isLoading = false;
      _addCurrentLocationCircle();
    }

    // 定期取得（例：15秒ごと）
    if (widget.locationPermissionGranted) {
      _reloadTimer = Timer.periodic(const Duration(seconds: 15), (timer) async {
        if (mapController == null) return;
        final bounds = await mapController!.getVisibleRegion();
        _loadPostsInBounds(bounds); // ← 実行する
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _moveToCurrentLocation();
    }
  }

  @override
  void dispose() {
    _reloadTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _textController.dispose();
    super.dispose();
  }

  // ---------- 位置情報まわり ----------

  Future<void> _getCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        currentPosition = position;
        isLoading = false;
        _addCurrentLocationCircle();
      });

      await _postInitialMessagesIfNeeded(); // ← 条件付きサンプル投入（ダミーユーザーで）
    } catch (e) {
      setState(() {
        isLoading = false;
      });
    }
  }

  /// 近傍の“親投稿（parent == null）”件数を数える（半径50m・直近24h）
  Future<int> _fetchNearbyParentCount50m(double lat, double lng) async {
    const radiusM = 50.0;

    // 半径50mをカバーする極小BBox → geohash6セルを最大10個
    final dLat = radiusM / 111000.0;
    final dLng = radiusM / (111000.0 * cos(lat * pi / 180.0));
    final cells = gh.GeohashUtil.getGeohashBox(
            lat - dLat, lng - dLng, lat + dLat, lng + dLng, 6)
        .take(10)
        .toList();
    if (cells.isEmpty) return 0;

    final snap = await FirebaseFirestore.instance
        .collection('posts')
        .where('isDeleted', isEqualTo: false)
        .where('geohash', whereIn: cells)
        .get();

    // 24時間以内 & 親投稿のみ & 厳密距離50m以内
    final since = DateTime.now().subtract(const Duration(hours: 24));
    return snap.docs.map((d) => Post.fromFirestore(d)).where((p) {
      if (p.position == null) return false;
      if (p.parent != null) return false; // 親投稿のみ
      final created = (p.createdAt is Timestamp)
          ? (p.createdAt as Timestamp).toDate()
          : (p.createdAt is DateTime ? p.createdAt as DateTime : null);
      if (created == null || created.isBefore(since)) return false;

      final dist = Geolocator.distanceBetween(
          lat, lng, p.position!.latitude, p.position!.longitude);
      return dist <= radiusM;
    }).length;
  }

  // 初期投稿（サンプル）が未投入なら、条件を満たすときに一度だけ投入
  // 条件：① 近傍（半径50m・直近24h）に親投稿がない ② インストール毎に一回だけ
  // ※ ダミーユーザー（ID=10000）で投稿します
  Future<void> _postInitialMessagesIfNeeded() async {
    if (!widget.locationPermissionGranted) return;
    if (currentPosition == null) return;

    final prefs = await SharedPreferences.getInstance();
    // インストール毎に一回だけ
    if (prefs.getBool('seeded_install_once') == true) return;

    final lat = currentPosition!.latitude;
    final lng = currentPosition!.longitude;

    // 近傍（半径50m・直近24h）に親投稿が1件でもあればシードしない
    final nearbyCount = await _fetchNearbyParentCount50m(lat, lng);
    if (nearbyCount > 0) {
      await prefs.setBool('seeded_install_once', true);
      return;
    }

    // ここからサンプル投入（現状仕様を踏襲して3件）
    // Cloud Functions を呼び出し、AIからメッセージを取得する
    List<String> texts = [];

    try {
      // 端末のロケールに応じて言語を決定
      final code = Localizations.localeOf(context).languageCode;
      final lang = code == 'en' ? '英語' : '日本語';

      texts = await PostService().fetchAiMessages(
          count: 3, position: GeoPoint(lat, lng), language: lang);

      print(texts);

      if (texts.isEmpty) {
        // メッセージが0件なら何もしない
        return;
      }
    } on FirebaseFunctionsException catch (e) {
      // エラー時はログを出して終了
      print('fetchAiMessages エラー: ${e.message}');
      return;
    } catch (e) {
      print('fetchAiMessages 予期せぬエラー: $e');
      return;
    }

    const double radiusInMeters = 50;
    final double radiusInDegrees = radiusInMeters / 111000;

    int success = 0;
    for (final text in texts) {
      final angle = Random().nextDouble() * 2 * pi;
      final u = Random().nextDouble();
      final r = radiusInDegrees * sqrt(u);
      final dy = r * sin(angle);
      final dx = r * cos(angle) / cos(lat * pi / 180);

      final latOffset = lat + dy;
      final lngOffset = lng + dx;

      try {
        await PostService().addPost(
          userId: kDummyUserId, // ★ ダミー固定
          text: text,
          posterName: kDummyPosterName, // ★ ダミー表示名
          position: GeoPoint(latOffset, lngOffset),
          submissionKey: PostService.generateSubmissionKey(),
          address: '住所不明',
        );
        success++;
      } catch (_) {/* no-op */}
    }

    if (success > 0) {
      await prefs.setBool('seeded_install_once', true);
      // 反映
      _onCameraIdle();
    }
  }

  Future<void> _refreshCurrentLocation() async {
    if (!widget.locationPermissionGranted) return;
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        currentPosition = pos;
        _addCurrentLocationCircle();
      });
    } catch (_) {}
  }

  void _addCurrentLocationCircle() {
    final center = _currentTarget;
    circles.clear();
    circles.add(
      Circle(
        circleId: const CircleId('currentLocationCircle'),
        center: center,
        radius: 50, // 位置サークル
        fillColor: const Color(0xFF2196F3).withOpacity(0.20),
        strokeColor: const Color(0xFF2196F3),
        strokeWidth: 2,
      ),
    );
    setState(() {});
    // ※ 現在地サークルは 50m 固定（仕様）
  }

  void _moveToCurrentLocation() async {
    if (!widget.locationPermissionGranted) {
      mapController?.animateCamera(
        CameraUpdate.newLatLng(_defaultLocation),
      );
      return;
    }
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      mapController?.animateCamera(
        CameraUpdate.newLatLng(LatLng(position.latitude, position.longitude)),
      );
      setState(() {
        currentPosition = position;
        _addCurrentLocationCircle();
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('現在地を取得できませんでした')),
      );
    }
  }

  // ---------- 可視範囲／マーカー間引きヘルパー ----------

  // 日付変更線またぎも考慮した bounds 判定
  bool _isWithinBounds(LatLng p, LatLngBounds b) {
    final inLat = p.latitude >= b.southwest.latitude &&
        p.latitude <= b.northeast.latitude;

    final swLng = b.southwest.longitude;
    final neLng = b.northeast.longitude;
    final inLng = (swLng <= neLng)
        ? (p.longitude >= swLng && p.longitude <= neLng)
        : (p.longitude >= swLng || p.longitude <= neLng);

    return inLat && inLng;
  }

  // Firestore側に存在しない（=aliveに含まれない）親投稿マーカーを可視範囲内だけ間引く
  void _pruneMissingMarkers({
    required LatLngBounds bounds,
    required Set<String> aliveParentIds,
  }) {
    if (_markerMap.isEmpty) return;

    final removeIds = <String>[];
    _markerMap.forEach((postId, marker) {
      final inView = _isWithinBounds(marker.position, bounds);
      final alive = aliveParentIds.contains(postId);
      if (inView && !alive) {
        removeIds.add(postId);
      }
    });

    if (removeIds.isNotEmpty) {
      for (final id in removeIds) {
        _markerMap.remove(id);
      }
      setState(() {});
    }
  }

  // 投稿リストを bounds 内だけに厳密化（経度は日付変更線またぎ対応）
  List<Post> _filterPostsToBounds(List<Post> posts, LatLngBounds bounds) {
    final sw = bounds.southwest;
    final ne = bounds.northeast;
    final swLng = sw.longitude;
    final neLng = ne.longitude;
    final wraps = swLng > neLng; // 日付変更線跨ぎ

    return posts.where((post) {
      final lat = post.latitude;
      final lng = post.longitude;
      if (lat == null || lng == null) return false;

      final inLat = lat >= sw.latitude && lat <= ne.latitude;
      final inLng = wraps
          ? (lng >= swLng || lng <= neLng)
          : (lng >= swLng && lng <= neLng);

      return inLat && inLng;
    }).toList();
  }

  // ---------- 投稿表示（マーカー生成） ----------

  Future<void> _displayPosts(List<Post> allPosts) async {
    await _refreshCurrentLocation();

    // 親投稿とコメント数（親ID→件数）
    final posts = allPosts.where((p) => p.parent == null).toList();
    final Map<String, int> commentCounts = {};
    for (final c in allPosts.where((p) => p.parent != null)) {
      final parentId = c.parent!;
      commentCounts[parentId] = (commentCounts[parentId] ?? 0) + 1;
    }

    final markerService = MapMarkerService();

    // 取得結果に含まれないマーカーは削除しない方針だが、
    // Firestore側で手動削除された分は後段の _pruneMissingMarkers で可視範囲内のみ間引く。
    await for (final marker in markerService.streamMarkersFromPosts(
      posts: posts,
      commentCounts: commentCounts,
      onMarkerTap: (post) async {
        await _refreshCurrentLocation();
        await showPostDialog(context, post, currentPosition, enableReply: true,
            onPosted: () async {
          if (mapController != null) {
            final bounds = await mapController!.getVisibleRegion();
            _loadPostsInBounds(bounds);
          }
        });
        _onCameraIdle();
      },
    )) {
      _markerMap[marker.markerId.value] = marker;
      setState(() {});

      // マーカーが増えすぎないように古いものを間引く（上限500）
      while (_markerMap.length > 500) {
        _markerMap.remove(_markerMap.keys.first);
      }
    }

    _addCurrentLocationCircle();
  }

  // ---------- 可視範囲変化ハンドラ ----------

  void _onCameraIdle() async {
    if (!widget.locationPermissionGranted) return;
    if (mapController == null) return;
    final bounds = await mapController!.getVisibleRegion();
    _loadPostsInBounds(bounds);
  }

  // ---------- Firestore/ローカル同期 & マーカー間引きの中核 ----------

  Future<void> _loadPostsInBounds(LatLngBounds bounds) async {
    if (!widget.locationPermissionGranted) return;
    if (_fetchingPosts) return; // 多重実行ガード
    _fetchingPosts = true;

    try {
      try {
        final maintenanceSnapshot = await FirebaseFirestore.instance
            .collection('app_config')
            .doc('maintenance')
            .get();
        final maintenanceData = maintenanceSnapshot.data();
        if (maintenanceData?['enabled'] == true) {
          if (mounted && !_navigatedToMaintenance) {
            _navigatedToMaintenance = true;
            final messageData =
                maintenanceData?['messages'] ?? maintenanceData?['message'];
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (_) => MaintenancePage(messageData: messageData),
              ),
              (route) => false,
            );
          }
          return;
        } else {
          _navigatedToMaintenance = false;
        }
      } catch (error) {
        if (kDebugMode) {
          debugPrint('メンテナンス状態の確認に失敗: $error');
        }
      }

      final postsReference = FirebaseFirestore.instance.collection('posts');
      final southWest = bounds.southwest;
      final northEast = bounds.northeast;

      // 1) まずローカルDBから表示（体感改善）
      final localPosts = await PostCacheDb.instance.getPostsInBounds(
        southWest.latitude,
        southWest.longitude,
        northEast.latitude,
        northEast.longitude,
      );
      if (localPosts.isNotEmpty) {
        await _displayPosts(localPosts);
      }

      // 2) geohash セルを 10件以内に収める（精度を下げて調整）
      int precision = 6;
      List<String> boundingHashes;
      do {
        boundingHashes = gh.GeohashUtil.getGeohashBox(
          southWest.latitude,
          southWest.longitude,
          northEast.latitude,
          northEast.longitude,
          precision,
        ).toList();
        if (boundingHashes.length > 10) precision--;
      } while (boundingHashes.length > 10 && precision >= 1);

      if (boundingHashes.isEmpty) {
        // セルが作れない場合は終了（まれ）
        return;
      }

      // 3) Firestore 取得（geohash範囲）
      final snapshot = await postsReference
          .where('isDeleted', isEqualTo: false)
          .where('geohash', whereIn: boundingHashes)
          .get();

      // 4) 厳密に bounds 内へ（緯度経度でフィルタ：日付変更線跨ぎ対応）
      final fetched = snapshot.docs.map((d) => Post.fromFirestore(d)).toList();
      final allPosts = _filterPostsToBounds(fetched, bounds);

      // 5) ローカルDBに同期（欠損＝削除扱い → upsert）
      final remoteIds = allPosts.map((p) => p.id).toSet();
      await PostCacheDb.instance.markMissingInBoundsAsDeleted(
        southWest.latitude,
        southWest.longitude,
        northEast.latitude,
        northEast.longitude,
        remoteIds,
      );
      await PostCacheDb.instance.upsertPosts(allPosts);

      // 6) 可視範囲における “生存親投稿ID” を作成して、マーカーを間引く
      final aliveParentIds =
          allPosts.where((p) => p.parent == null).map((p) => p.id).toSet();
      _pruneMissingMarkers(bounds: bounds, aliveParentIds: aliveParentIds);

      // 7) ローカルDBの最新状態で再描画（削除反映後の確定状態）
      final refreshedLocal = await PostCacheDb.instance.getPostsInBounds(
        southWest.latitude,
        southWest.longitude,
        northEast.latitude,
        northEast.longitude,
      );
      await _displayPosts(refreshedLocal);
    } finally {
      _fetchingPosts = false;
    }
  }

  // ---------- 投稿（送信） ----------

  Future<void> _submitPost() async {
    if (_isPosting) return; // 二重送信防止
    if (!widget.locationPermissionGranted) return;

    await _refreshCurrentLocation();

    final rawText = _textController.text.trim();
    if (rawText.isEmpty || currentPosition == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final lat = currentPosition!.latitude;
    final lng = currentPosition!.longitude;

    // 逆ジオコーディング（失敗時は住所不明）
    String address = '住所不明';
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        address =
            '${place.subLocality}, ${place.locality}, ${place.administrativeArea}, ${place.country}';
      }
    } catch (_) {}

    // 半径50m内のランダム配置（均一分布）
    const double radiusInMeters = 50;
    final double radiusInDegrees = radiusInMeters / 111000;
    final double angle = Random().nextDouble() * 2 * pi;
    final double u = Random().nextDouble();
    final double r = radiusInDegrees * sqrt(u);
    final double dy = r * sin(angle);
    final double dx = r * cos(angle) / cos(lat * pi / 180);

    final latOffset = lat + dy;
    final lngOffset = lng + dx;
    final position = GeoPoint(latOffset, lngOffset);

    setState(() {
      _isPosting = true;
    });

    try {
      await PostService().addPost(
        userId: user.uid, // ← 通常投稿はユーザー本人
        text: rawText,
        posterName: '名無し',
        position: position,
        submissionKey: _submissionKey,
        address: address,
      );

      _submissionKey = PostService.generateSubmissionKey();
      _textController.clear();
      _onCameraIdle(); // 投稿後に再取得
    } on DuplicateSubmissionException {
      _submissionKey = PostService.generateSubmissionKey();
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('投稿に失敗しました。時間をおいて再度お試しください。'),
        ),
      );
    } finally {
      setState(() {
        _isPosting = false;
      });
    }
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final canAccessLocation = widget.locationPermissionGranted;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FB),
      body: Stack(
        children: [
          // Google Map
          Positioned.fill(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : GoogleMap(
                    onMapCreated: (controller) {
                      mapController = controller;
                    },
                    minMaxZoomPreference: const MinMaxZoomPreference(16, null),
                    onCameraIdle: _onCameraIdle,
                    myLocationEnabled: false,
                    myLocationButtonEnabled: false,
                    initialCameraPosition: CameraPosition(
                      target: _currentTarget,
                      zoom: 18,
                    ),
                    markers: markers,
                    circles: circles,
                  ),
          ),

          if (!canAccessLocation)
            Positioned(
              left: 16,
              right: 16,
              top: 110,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.75),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  AppLocalizations.of(context)!
                      .locationPermissionLimitedMessage,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ),
            ),

          // LooQNロゴ（左上）
          Positioned(
            left: 16,
            top: 50,
            child: ClipOval(
              child: Image.asset(
                'assets/app_icon.png',
                width: 48,
                height: 48,
                fit: BoxFit.cover,
              ),
            ),
          ),

          // 右下FAB（現在地・マイページ・サークル一覧・履歴）
          Positioned(
            right: 18,
            bottom: 120,
            child: Column(
              children: [
                // 現在地
                FloatingActionButton(
                  heroTag: 'mylocation',
                  mini: true,
                  onPressed: canAccessLocation ? _moveToCurrentLocation : null,
                  backgroundColor: Colors.white,
                  shape: CircleBorder(
                    side: BorderSide(color: looqnBlue, width: 2),
                  ),
                  child: Icon(Icons.my_location, color: looqnBlue),
                ),
                const SizedBox(height: 16),

                // マイページ
                FloatingActionButton(
                  heroTag: 'mypage',
                  mini: true,
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      useRootNavigator: true,
                      builder: (context) => FractionallySizedBox(
                        heightFactor: 0.95,
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(24)),
                          child: Builder(builder: (context) => MyPage()),
                        ),
                      ),
                    );
                  },
                  backgroundColor: Colors.white,
                  shape: CircleBorder(
                    side: BorderSide(color: looqnBlue, width: 2),
                  ),
                  child: Icon(Icons.person, color: looqnBlue),
                ),
                const SizedBox(height: 16),

                // サークル内一覧
                FloatingActionButton(
                  heroTag: 'circleList',
                  mini: true,
                  onPressed: canAccessLocation
                      ? () async {
                    Position? pos;
                    try {
                      pos = await Geolocator.getCurrentPosition();
                    } catch (_) {
                      pos = null;
                    }
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (context) => FractionallySizedBox(
                        heightFactor: 0.95,
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(24)),
                          child: CirclePostsPage(position: pos),
                        ),
                      ),
                    );
                  }
                      : null,
                  backgroundColor: Colors.white,
                  shape: CircleBorder(
                    side: BorderSide(color: looqnBlue, width: 2),
                  ),
                  child: Icon(Icons.list, color: looqnBlue),
                ),
                const SizedBox(height: 16),

                // 履歴
                FloatingActionButton(
                  heroTag: 'history',
                  mini: true,
                  onPressed: () {
                    final user = FirebaseAuth.instance.currentUser;
                    if (user == null) return;
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (context) => FractionallySizedBox(
                        heightFactor: 0.95,
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(24)),
                          child: UserPostsPage(userId: user.uid),
                        ),
                      ),
                    );
                  },
                  backgroundColor: Colors.white,
                  shape: CircleBorder(
                    side: BorderSide(color: looqnBlue, width: 2),
                  ),
                  child: Icon(Icons.history, color: looqnBlue),
                ),
              ],
            ),
          ),

          // 投稿フォーム（中央下）
          Positioned(
            left: 0,
            right: 0,
            bottom: 32,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: MediaQuery.of(context).size.width * 0.96,
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
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
                        controller: _textController,
                        enabled: canAccessLocation,
                        decoration: InputDecoration(
                          hintText:
                              AppLocalizations.of(context)!.whatIsHappeningHere,
                          border: InputBorder.none,
                          hintStyle: const TextStyle(
                            color: Color(0xFF90A4AE),
                            fontSize: 16,
                          ),
                        ),
                        style: const TextStyle(fontSize: 18),
                      ),
                    ),
                    GestureDetector(
                      onTap:
                          _isPosting || !canAccessLocation ? null : _submitPost,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: looqnBlue,
                          shape: BoxShape.circle,
                        ),
                        child: _isPosting
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
            ),
          ),
        ],
      ),
      bottomNavigationBar: const AdBanner(),
    );
  }

  LatLng get _currentTarget {
    if (currentPosition != null) {
      return LatLng(currentPosition!.latitude, currentPosition!.longitude);
    }
    return _defaultLocation;
  }
}
