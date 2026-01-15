// lib/widgets/ad_banner.dart
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../ad_helper.dart';

class AdBanner extends StatefulWidget {
  const AdBanner({super.key});

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    if (!AdHelper.enableAds) {
      return; // スクリーンショット用などで無効化された場合はなにもしない
    }
    _load();
  }

  Future<void> _load() async {
    // まずは固定バナーで安定運用（必要に応じて Adaptive に切替）
    final ad = BannerAd(
      adUnitId: AdHelper.bannerUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) return;
          setState(() {
            _bannerAd = ad as BannerAd;
            _isLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose(); // 失敗時は静かに破棄（UIは非表示のまま）
          // 必要ならログ出力のみ（UXを壊さない）
        },
      ),
    );

    await ad.load();
  }

  @override
  Widget build(BuildContext context) {
    if (!AdHelper.enableAds || !_isLoaded || _bannerAd == null) {
      return const SizedBox.shrink(); // 読み込み前/失敗時は空でOK（レイアウト崩れ回避）
    }

    final w = _bannerAd!.size.width.toDouble();
    final h = _bannerAd!.size.height.toDouble();

    return SafeArea(
      top: false,
      child: SizedBox(
        width: w,
        height: h,
        child: AdWidget(ad: _bannerAd!),
      ),
    );
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }
}
