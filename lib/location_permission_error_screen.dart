import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'location_permission_status.dart';

/// 位置情報許可エラー用の画面
class LocationPermissionErrorScreen extends StatelessWidget {
  const LocationPermissionErrorScreen({
    super.key,
    required this.errorType,
    required this.onClose,
  });

  final LocationPermissionErrorType? errorType;
  final VoidCallback onClose;

  String _buildMessage(AppLocalizations loc) {
    switch (errorType) {
      case LocationPermissionErrorType.serviceDisabled:
        return loc.locationServiceDisabledMessage;
      case LocationPermissionErrorType.deniedForever:
        return loc.locationPermissionDeniedForeverMessage;
      case LocationPermissionErrorType.denied:
      default:
        return loc.locationPermissionDeniedMessage;
    }
  }

  Future<void> _openSettings() async {
    if (errorType == LocationPermissionErrorType.serviceDisabled) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.location_off,
                size: 72,
                color: Colors.redAccent,
              ),
              const SizedBox(height: 24),
              Text(
                loc.locationPermissionTitle,
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                _buildMessage(loc),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await _openSettings();
                  },
                  icon: const Icon(Icons.settings),
                  label: Text(loc.openSettings),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onClose,
                  child: Text(loc.close),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
