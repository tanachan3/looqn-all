import 'dart:async';
import 'dart:io'; // iOS/Androidの判別に必要

// 多言語対応の追加
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

// チュートリアル用
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geomsg_chat/tutorial_screen.dart';

// ログイン画面
import 'package:geomsg_chat/login_screen.dart'; // ←追加

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:workmanager/workmanager.dart'; // 追加
import 'package:flutter/foundation.dart'; // 追加
import 'package:geomsg_chat/ad_helper.dart';
import 'package:geomsg_chat/location_service.dart';
import 'package:geomsg_chat/location_permission_error_screen.dart';
import 'package:geomsg_chat/location_permission_status.dart';
import 'package:geomsg_chat/firebase_options.dart' as firebase_config;
import 'package:geomsg_chat/maintenance_page.dart';
import 'package:geomsg_chat/map.dart';
import 'package:geomsg_chat/read_status_db.dart';
import 'package:geomsg_chat/post_cache_db.dart';

import 'package:google_mobile_ads/google_mobile_ads.dart'; // ★ AdMob

// Background task names
const String locationTaskName = 'locationTask';
const String purgeDbTaskName = 'purgeLocalDbTask';

bool _firebaseOptionsEquals(FirebaseOptions a, FirebaseOptions b) {
  return a.appId == b.appId &&
      a.apiKey == b.apiKey &&
      a.projectId == b.projectId &&
      a.messagingSenderId == b.messagingSenderId &&
      a.storageBucket == b.storageBucket &&
      a.androidClientId == b.androidClientId &&
      a.iosClientId == b.iosClientId &&
      a.iosBundleId == b.iosBundleId &&
      a.trackingId == b.trackingId &&
      a.databaseURL == b.databaseURL &&
      a.measurementId == b.measurementId;
}

Future<FirebaseApp> _safeInitializeFirebase(FirebaseOptions options) async {
  FirebaseApp? existingApp;
  try {
    existingApp = Firebase.app();
    if (_firebaseOptionsEquals(existingApp.options, options)) {
      if (kDebugMode) {
        debugPrint('Firebaseアプリは既に同一オプションで初期化済みのため再利用します。');
      }
      return existingApp;
    }
  } on FirebaseException catch (error) {
    if (error.code != 'no-app') {
      rethrow;
    }
  }

  try {
    return await Firebase.initializeApp(options: options);
  } on FirebaseException catch (error) {
    if (error.code != 'duplicate-app') {
      rethrow;
    }

    existingApp ??= Firebase.app();
    if (_firebaseOptionsEquals(existingApp.options, options)) {
      if (kDebugMode) {
        debugPrint('Firebaseアプリは既に同一オプションで初期化済みのため再利用します。');
      }
      return existingApp;
    }

    if (Platform.isIOS || Platform.isMacOS) {
      if (kDebugMode) {
        debugPrint(
          'iOS/macOSでは既定アプリの再初期化がサポートされないため既存構成'
          '(${existingApp.options.projectId})を再利用します。',
        );
      }
      return existingApp;
    }

    if (kDebugMode) {
      debugPrint(
        '既存のFirebaseアプリ構成(${existingApp.options.projectId})と要求された構成'
        '(${options.projectId})が一致しないため再初期化を試みます。',
      );
    }

    try {
      await existingApp.delete();
    } on Exception catch (deleteError) {
      if (kDebugMode) {
        debugPrint('既存Firebaseアプリの破棄に失敗しました: $deleteError');
      }
      rethrow;
    }

    return Firebase.initializeApp(options: options);
  }
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await _safeInitializeFirebase(
    firebase_config.DefaultFirebaseOptions.currentPlatform,
  );
  // Background message handling logic
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    await _safeInitializeFirebase(
      firebase_config.DefaultFirebaseOptions.currentPlatform,
    );
    if (task == locationTaskName) {
      if (Platform.isAndroid) {
        await getCurrentLocationAndSendToFirebase();
      }
    } else if (task == purgeDbTaskName) {
      await ReadStatusDb.instance.purgeOldEntries(const Duration(hours: 24));
      await PostCacheDb.instance.purgeOldEntries(const Duration(hours: 24));
    }
    return Future.value(true);
  });
}

/// ▼ 追加：広告SDKの初期化（OS共通でOK）
Future<void> _initAds() async {
  // ここで必要なら RequestConfiguration なども設定可能
  await MobileAds.instance.updateRequestConfiguration(
    RequestConfiguration(
      maxAdContentRating: MaxAdContentRating.pg, // 無難な表現制限
      tagForChildDirectedTreatment: TagForChildDirectedTreatment.unspecified,
      tagForUnderAgeOfConsent: TagForUnderAgeOfConsent.unspecified,
      // testDeviceIds: <String>[], // 必要ならテスト端末ID
    ),
  );
  await MobileAds.instance.initialize();
}

Future<void> runGeomsgApp({
  FirebaseOptions? firebaseOptions,
  firebase_config.AppFlavor? flavor,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  final resolvedFlavor = flavor ?? firebase_config.currentAppFlavor;
  firebase_config.setRuntimeAppFlavor(resolvedFlavor);
  final options =
      firebaseOptions ?? firebase_config.firebaseOptionsFor(resolvedFlavor);

  if (kDebugMode) {
    debugPrint('起動フレーバー: ${resolvedFlavor.name}');
    debugPrint('Firebase projectId: ${options.projectId} / appId: ${options.appId}');
  }

  final firebaseApp = await _safeInitializeFirebase(options);

  // App Check をフレーバーに合わせて有効化する
  if (resolvedFlavor == firebase_config.AppFlavor.prod) {
    await FirebaseAppCheck.instanceFor(app: firebaseApp).activate();
  } else {
    // devフレーバーではAPI未有効時の権限エラーを避けるためApp Checkを初期化しない
    if (kDebugMode) {
      debugPrint('devフレーバーではApp Checkをスキップします（API未有効時のエラー回避）');
    }
    try {
      await FirebaseAppCheck.instanceFor(app: firebaseApp)
          .setTokenAutoRefreshEnabled(false);
    } on Exception catch (error) {
      if (kDebugMode) {
        debugPrint('App Check スキップ処理に失敗しました: $error');
      }
    }
  }

  // ローカル既読DB初期化
  await ReadStatusDb.instance.init();
  await ReadStatusDb.instance.purgeOldEntries(const Duration(hours: 24));
  // 投稿キャッシュDB初期化
  await PostCacheDb.instance.init();
  await PostCacheDb.instance.purgeOldEntries(const Duration(hours: 24));

  final permissionStatus = await requestLocationPermission();

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  if (!kIsWeb && Platform.isAndroid) {
    Workmanager().initialize(callbackDispatcher, isInDebugMode: true);
    Workmanager().registerPeriodicTask(
      "1",
      locationTaskName,
      frequency: const Duration(minutes: 1),
      initialDelay: const Duration(seconds: 10),
    );

    final now = DateTime.now();
    DateTime firstRun = DateTime(now.year, now.month, now.day, now.hour, 5);
    if (!firstRun.isAfter(now)) {
      firstRun = firstRun.add(const Duration(hours: 1));
    }
    final delay = firstRun.difference(now);
    Workmanager().registerPeriodicTask(
      "2",
      purgeDbTaskName,
      frequency: const Duration(hours: 1),
      initialDelay: delay,
    );
  }

  // ★ 追加：広告SDK初期化
  if (AdHelper.enableAds) {
    await _initAds();
  } else if (kDebugMode) {
    debugPrint('ENABLE_ADS=false のため広告初期化をスキップしました');
  }

  runApp(
    MyApp(
      initialPermissionStatus: permissionStatus,
      flavor: resolvedFlavor,
    ),
  );
}

Future<void> main() async {
  await runGeomsgApp();
}

class MyApp extends StatefulWidget {
  const MyApp({
    super.key,
    required this.initialPermissionStatus,
    required this.flavor,
  });

  /// アプリ起動時点での位置情報認可状態
  final LocationPermissionStatus initialPermissionStatus;
  final firebase_config.AppFlavor flavor;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _isLoading = true;
  bool _isFirstLaunch = false;
  late LocationPermissionStatus _permissionStatus;
  bool _hasDismissedLocationPermission = false;
  bool _hasMaintenanceStatus = false;
  bool _isMaintenance = false;
  dynamic _maintenanceMessageData;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _maintenanceSubscription;

  @override
  void initState() {
    super.initState();
    _permissionStatus = widget.initialPermissionStatus;
    _checkFirstLaunch();
    _listenMaintenanceStatus();
  }

  Future<void> _checkFirstLaunch() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool? firstLaunch = prefs.getBool('is_first_launch');
    setState(() {
      _isFirstLaunch = (firstLaunch == null || firstLaunch == true);
      _isLoading = false;
    });
  }

  /// Firestoreのメンテナンスフラグを監視
  void _listenMaintenanceStatus() {
    _maintenanceSubscription?.cancel();
    _maintenanceSubscription = FirebaseFirestore.instance
        .collection('app_config')
        .doc('maintenance')
        .snapshots()
        .listen(
      (snapshot) {
        final data = snapshot.data();
        if (!mounted) {
          return;
        }
        setState(() {
          _hasMaintenanceStatus = true;
          _isMaintenance = data?['enabled'] == true;
          _maintenanceMessageData =
              data?['messages'] ?? data?['message'];
        });
      },
      onError: (error) {
        if (kDebugMode) {
          debugPrint('メンテナンス状態の取得に失敗: $error');
        }
        if (!mounted) {
          return;
        }
        setState(() {
          _hasMaintenanceStatus = true;
          _isMaintenance = false;
          _maintenanceMessageData = null;
        });
      },
    );
  }

  Future<void> _finishTutorial() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_first_launch', false);
    setState(() {
      _isFirstLaunch = false;
    });
  }

  MaterialApp _buildMaterialApp(Widget home) {
    return MaterialApp(
      debugShowCheckedModeBanner:
          widget.flavor != firebase_config.AppFlavor.prod,
      theme: ThemeData(),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ja'),
        Locale('en'),
      ],
      home: home,
    );
  }

  @override
  void dispose() {
    _maintenanceSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || !_hasMaintenanceStatus) {
      return _buildMaterialApp(
        const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    if (_isMaintenance) {
      return _buildMaterialApp(
        MaintenancePage(messageData: _maintenanceMessageData),
      );
    }

    if (!_permissionStatus.granted && !_hasDismissedLocationPermission) {
      return _buildMaterialApp(
        LocationPermissionErrorScreen(
          errorType: _permissionStatus.errorType,
          onClose: () {
            setState(() {
              _hasDismissedLocationPermission = true;
            });
          },
        ),
      );
    }

    return _buildMaterialApp(
      _isFirstLaunch
          ? TutorialScreen(onFinish: _finishTutorial)
          : AuthRoot(
              locationPermissionGranted: _permissionStatus.granted,
            ),
    );
  }
}

/// ログイン状態で画面を切り替える（LoginScreenは多言語UI）
class AuthRoot extends StatelessWidget {
  const AuthRoot({
    super.key,
    required this.locationPermissionGranted,
  });

  final bool locationPermissionGranted;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData) {
          return MapPage(
            locationPermissionGranted: locationPermissionGranted,
          );
        } else {
          return LoginScreen(); // ←ここでlogin_screen.dartのUIに
        }
      },
    );
  }
}
