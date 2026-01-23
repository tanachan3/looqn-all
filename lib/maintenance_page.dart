import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// メンテナンス画面
class MaintenancePage extends StatelessWidget {
  const MaintenancePage({super.key, this.messageData});

  /// Firestoreから取得したメンテナンス文言（文字列 or 言語コードごとのMap）
  final dynamic messageData;

  String? _resolveMessage(BuildContext context) {
    String? normalize(dynamic value) {
      if (value is String) {
        final trimmed = value.trim();
        if (trimmed.isNotEmpty) {
          return trimmed;
        }
      }
      return null;
    }

    final data = messageData;
    if (data == null) {
      return null;
    }

    if (data is String) {
      final normalized = normalize(data);
      if (normalized == null) {
        return null;
      }

      Map<dynamic, dynamic>? parseJsonMap(String candidate) {
        final trimmed = candidate.trim();
        if (!trimmed.startsWith('{') || !trimmed.endsWith('}')) {
          return null;
        }
        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is Map) {
            return decoded;
          }
        } catch (_) {
          // JSONとして解釈できなければ素の文字列を返す
        }
        return null;
      }

      final parsed = parseJsonMap(normalized);
      if (parsed != null) {
        return _resolveMessageFromMap(parsed, context);
      }

      return normalized;
    }

    if (data is Map) {
      return _resolveMessageFromMap(data, context);
    }

    return null;
  }

  String? _resolveMessageFromMap(
      Map<dynamic, dynamic> data, BuildContext context) {
    String? normalize(dynamic value) {
      if (value is String) {
        final trimmed = value.trim();
        if (trimmed.isNotEmpty) {
          return trimmed;
        }
      }
      return null;
    }

    String? byKey(String key) {
      final value = data[key] ?? data[key.toString()];
      return normalize(value);
    }

    final localeCode = Localizations.maybeLocaleOf(context)?.languageCode;
    if (localeCode != null) {
      final localized = byKey(localeCode);
      if (localized != null) {
        return localized;
      }
    }

    for (final key in ['default', 'ja', 'en']) {
      final localized = byKey(key);
      if (localized != null) {
        return localized;
      }
    }

    for (final value in data.values) {
      final normalized = normalize(value);
      if (normalized != null) {
        return normalized;
      }
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final resolvedMessage =
        _resolveMessage(context) ?? l10n?.maintenanceDefaultMessage ?? '';
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.build,
                  size: 72,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  l10n?.maintenanceTitle ?? 'Maintenance',
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  resolvedMessage,
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
