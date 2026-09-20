/// AdReward Attribution SDK for Flutter.
///
/// Zero platform channels. On app open it reports an install to AdReward; if
/// AdReward recognises the opener as a user who recently clicked the campaign
/// (matched server-side by IP within the attribution window), it returns a
/// one-time claim URL. That URL is opened in the EXTERNAL browser so the
/// customer's existing AdReward session on earn4rmads.com is reused — they
/// never log in again. Organic installs get `no_match` and nothing is shown.
///
/// Usage (call once, early in startup):
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await AdReward.init(trackingId: 'ADR-XXXXXX');
///   runApp(const MyApp());
/// }
/// ```
///
/// Recommended for App Store review — show your own prompt instead of sending
/// the customer straight to a browser on launch:
/// ```dart
/// await AdReward.init(
///   trackingId: 'ADR-XXXXXX',
///   onClaimAvailable: (claimUrl) => showMyDialog(claimUrl),
/// );
/// ```
library;

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class AdReward {
  static const _defaultApiBase = 'https://api.earn4rmads.com';
  static const _deviceIdKey = 'adr_device_id';
  static const _settledKey = 'adr_attr_settled';
  static const _firstSeenKey = 'adr_attr_first_seen';

  /// Fire attribution. Safe to call on every app start — it self-guards, never
  /// throws into the host app, and goes quiet once the outcome is settled.
  ///
  /// [onClaimAvailable] is called instead of opening the browser directly.
  /// Strongly recommended: present your own in-app prompt and launch the URL on
  /// a user tap. Apple reviewers dislike an app that opens a browser on its own
  /// at startup, and an unexplained jump to Safari reads as a bug to customers.
  ///
  /// [retryWindowHours] bounds how long an unmatched open keeps retrying. It
  /// must not exceed the server's attribution window (72h by default) — past
  /// that the click can no longer be honoured.
  static Future<void> init({
    required String trackingId,
    String apiBase = _defaultApiBase,
    String? platform,
    void Function(String claimUrl)? onClaimAvailable,
    int retryWindowHours = 72,
    Duration timeout = const Duration(seconds: 10),
    bool debug = false,
  }) async {
    void log(Object m) {
      if (debug) {
        // ignore: avoid_print
        print('[AdReward] $m');
      }
    }

    try {
      final prefs = await SharedPreferences.getInstance();

      if (prefs.getBool(_settledKey) == true) {
        log('already settled — skipping');
        return;
      }

      // An unmatched open is not final: the customer may have clicked on one
      // network and first opened the app on another, and the server re-runs the
      // IP gate on later opens. Keep asking until the attribution window is up.
      final firstSeen = await _firstSeen(prefs);
      final elapsed = DateTime.now().millisecondsSinceEpoch - firstSeen;
      if (elapsed > retryWindowHours * 3600 * 1000) {
        log('attribution window elapsed — settling');
        await prefs.setBool(_settledKey, true);
        return;
      }

      // defaultTargetPlatform rather than dart:io Platform, so the package also
      // imports cleanly on web.
      final plat = platform ??
          (defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android');
      final deviceId = await _deviceId(prefs);
      final base = apiBase.replaceAll(RegExp(r'/+$'), '');

      final resp = await http
          .post(
            Uri.parse('$base/api/v1/sdk/install'),
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'tracking_id': trackingId,
              'platform': plat,
              'device_id': deviceId,
            }),
          )
          // Never let a hanging network hold up app startup.
          .timeout(timeout);

      final decoded = jsonDecode(resp.body);
      final data = (decoded is Map && decoded['data'] is Map)
          ? decoded['data'] as Map
          : const {};
      log('install response $data');

      final claimUrl = data['claim_url'];
      if (claimUrl is String && claimUrl.isNotEmpty) {
        if (onClaimAvailable != null) {
          onClaimAvailable(claimUrl);
        } else {
          // External browser (never an in-app WebView) so the customer's
          // AdReward session is reused and they skip logging in.
          await launchUrl(
            Uri.parse(claimUrl),
            mode: LaunchMode.externalApplication,
          );
        }

        // The claim was surfaced; do not surface it again on this device.
        await prefs.setBool(_settledKey, true);
        return;
      }

      // `already_attributed` means this device is spent — stop asking. A plain
      // `no_match` is still open, so we retry on the next cold start until the
      // window above runs out.
      if (data['status'] == 'already_attributed') {
        log('device already attributed — settling');
        await prefs.setBool(_settledKey, true);
      }
    } catch (e) {
      // Never break the host app. Not settling means we retry on the next open.
      log('error (will retry next open) $e');
    }
  }

  /// Testing helper: clear local state so [init] runs again on the next call.
  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_deviceIdKey);
    await prefs.remove(_settledKey);
    await prefs.remove(_firstSeenKey);
  }

  /// First time we ran on this device, as epoch ms. Bounds how long an
  /// unmatched install keeps retrying.
  static Future<int> _firstSeen(SharedPreferences prefs) async {
    final stored = prefs.getInt(_firstSeenKey);
    if (stored != null) {
      return stored;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    await prefs.setInt(_firstSeenKey, now);
    return now;
  }

  static Future<String> _deviceId(SharedPreferences prefs) async {
    var id = prefs.getString(_deviceIdKey);
    if (id == null) {
      id = _uuidV4();
      await prefs.setString(_deviceIdKey, id);
    }
    return id;
  }

  /// RFC4122-ish v4 uuid — a per-install device id, not security-critical.
  static String _uuidV4() {
    final r = Random();
    String seg(int len) {
      final b = StringBuffer();
      for (var i = 0; i < len; i++) {
        b.write(r.nextInt(16).toRadixString(16));
      }
      return b.toString();
    }

    final variant = (8 + r.nextInt(4)).toRadixString(16);
    return '${seg(8)}-${seg(4)}-4${seg(3)}-$variant${seg(3)}-${seg(12)}';
  }
}
