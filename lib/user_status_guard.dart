import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:geomsg_chat/post_cache_db.dart';
import 'package:geomsg_chat/read_status_db.dart';
import 'package:geomsg_chat/util.dart';

class UserStatusGuard {
  static bool _isRedirecting = false;

  static Future<bool> ensureActiveOrRedirect(
    BuildContext context, {
    bool showMessage = false,
  }) async {
    if (_isRedirecting) {
      return false;
    }

    final loc = AppLocalizations.of(context)!;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      await _handleInactive(
        context,
        showMessage: showMessage,
        message: showMessage ? loc.userStatusWithdrawnMessage : null,
        reason: loc.userStatusAuthUserMissing,
      );
      return false;
    }

    try {
      final userDocId = await getCurrentUserDocId();
      if (userDocId == null) {
        await _handleInactive(
          context,
          showMessage: showMessage,
          message: showMessage ? loc.userStatusWithdrawnMessage : null,
          reason: loc.userStatusDocIdMissing,
        );
        return false;
      }
      var snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userDocId)
          .get();
      if (!snapshot.exists) {
        await Future.delayed(const Duration(milliseconds: 800));
        snapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(userDocId)
            .get();
        if (!snapshot.exists) {
          await _handleInactive(
            context,
            showMessage: showMessage,
            message: showMessage ? loc.userStatusWithdrawnMessage : null,
            reason: loc.userStatusDocMissing,
          );
          return false;
        }
      }

      final data = snapshot.data();
      final isDeleted = data?['isDeleted'] == true;
      final status = (data?['status'] as String?)?.toLowerCase();
      final deletedAt = data?['deletedAt'];
      final isStatusDeleted = status == 'withdrawn' ||
          status == 'deleted' ||
          status == 'disabled';
      final hasDeletedAt = deletedAt != null;
      if (isDeleted || isStatusDeleted || hasDeletedAt) {
        await _handleInactive(
          context,
          showMessage: showMessage,
          message: showMessage ? loc.userStatusWithdrawnMessage : null,
          reason: loc.userStatusInvalid,
        );
        return false;
      }

      return true;
    } on FirebaseException catch (error) {
      return true;
    } catch (error) {
      return true;
    }
  }

  static Future<void> _handleInactive(
    BuildContext context, {
    required bool showMessage,
    String? message,
    String? reason,
  }) async {
    if (_isRedirecting) {
      return;
    }
    _isRedirecting = true;
    try {
      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {}

      try {
        final googleSignIn = GoogleSignIn();
        await googleSignIn.signOut();
        await googleSignIn.disconnect();
      } catch (_) {}

      await clearCurrentUserDocId();
      await ReadStatusDb.instance.clearAll();
      await PostCacheDb.instance.clearAll();

      if (!context.mounted) {
        return;
      }

      if (showMessage) {
        if (message != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
            ),
          );
        }
      }

      Navigator.of(context).popUntil((route) => route.isFirst);
    } finally {
      _isRedirecting = false;
    }
  }

  static Future<void> handlePenalty(
    BuildContext context, {
    bool showMessage = true,
    String? message,
  }) async {
    final loc = AppLocalizations.of(context)!;
    await _handleInactive(
      context,
      showMessage: showMessage,
      message: message ?? loc.userStatusPenaltyMessage,
    );
  }
}
