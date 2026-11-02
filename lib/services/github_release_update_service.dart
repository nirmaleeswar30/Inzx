import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode, kReleaseMode;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

class GithubReleaseInfo {
  const GithubReleaseInfo({
    required this.latestVersion,
    required this.releaseUrl,
    required this.downloadUrl,
    this.body,
    this.releaseName,
  });

  final String latestVersion;
  final String releaseUrl;
  final String downloadUrl;
  final String? body;
  final String? releaseName;
}

/// Checks GitHub releases for a newer store-distributed app version.
class GithubReleaseUpdateService {
  GithubReleaseUpdateService._();

  static final GithubReleaseUpdateService instance =
      GithubReleaseUpdateService._();

  static const String _defaultRepo = 'nirmaleeswar30/Inzx';

  static String get _repo {
    final fromEnv = dotenv.env['GITHUB_RELEASE_REPO']?.trim() ?? '';
    return fromEnv.isNotEmpty ? fromEnv : _defaultRepo;
  }

  static String get _latestReleaseApi {
    final fromEnv = dotenv.env['GITHUB_RELEASE_API_URL']?.trim() ?? '';
    if (fromEnv.isNotEmpty) return fromEnv;
    return 'https://api.github.com/repos/$_repo/releases/latest';
  }

  static String get _fallbackReleaseUrl {
    final fromEnv = dotenv.env['GITHUB_RELEASE_PAGE_URL']?.trim() ?? '';
    if (fromEnv.isNotEmpty) return fromEnv;
    return 'https://github.com/$_repo/releases/latest';
  }

  Future<GithubReleaseInfo?> checkForNewRelease({bool ignoreReleaseMode = true}) async {
    if (!kReleaseMode && !ignoreReleaseMode) return null;

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = _normalizeVersion(packageInfo.version);

      if (currentVersion.isEmpty) return null;

      final response = await http
          .get(
            Uri.parse(_latestReleaseApi),
            headers: const {
              'Accept': 'application/vnd.github+json',
              'X-GitHub-Api-Version': '2022-11-28',
              'User-Agent': 'Inzx-App-Update-Checker',
            },
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        if (kDebugMode) {
          print(
            'GitHubRelease: API returned ${response.statusCode}, skipping check',
          );
        }
        return null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;

      final tag = (decoded['tag_name'] as String?)?.trim() ?? '';
      final releaseName = (decoded['name'] as String?)?.trim();
      final body = (decoded['body'] as String?)?.trim();
      final htmlUrl = (decoded['html_url'] as String?)?.trim();
      final latestVersion = _normalizeVersion(tag);
      final apkDownloadUrl = _pickInzxApkDownloadUrl(decoded['assets']);

      if (latestVersion.isEmpty) return null;

      final isNewer = _compareSemver(latestVersion, currentVersion) > 0;
      if (!isNewer) return null;

      return GithubReleaseInfo(
        latestVersion: latestVersion,
        releaseUrl: (htmlUrl != null && htmlUrl.isNotEmpty)
            ? htmlUrl
            : _fallbackReleaseUrl,
        downloadUrl: apkDownloadUrl ?? _fallbackReleaseUrl,
        body: body,
        releaseName: releaseName,
      );
    } catch (e) {
      if (kDebugMode) {
        print('GitHubRelease: Check failed: $e');
      }
      return null;
    }
  }

  Future<GithubReleaseInfo?> fetchLatestReleaseInfo() async {
    try {
      final response = await http
          .get(
            Uri.parse(_latestReleaseApi),
            headers: const {
              'Accept': 'application/vnd.github+json',
              'X-GitHub-Api-Version': '2022-11-28',
              'User-Agent': 'Inzx-App-Update-Checker',
            },
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;

      final tag = (decoded['tag_name'] as String?)?.trim() ?? '';
      final releaseName = (decoded['name'] as String?)?.trim();
      final body = (decoded['body'] as String?)?.trim();
      final htmlUrl = (decoded['html_url'] as String?)?.trim();
      final latestVersion = _normalizeVersion(tag);
      final apkDownloadUrl = _pickInzxApkDownloadUrl(decoded['assets']);

      return GithubReleaseInfo(
        latestVersion: latestVersion.isNotEmpty ? latestVersion : '1.0.0',
        releaseUrl: (htmlUrl != null && htmlUrl.isNotEmpty)
            ? htmlUrl
            : _fallbackReleaseUrl,
        downloadUrl: apkDownloadUrl ?? _fallbackReleaseUrl,
        body: body,
        releaseName: releaseName,
      );
    } catch (e) {
      if (kDebugMode) {
        print('GitHubRelease: fetchLatestReleaseInfo failed: $e');
      }
      return null;
    }
  }

  String _normalizeVersion(String value) {
    var v = value.trim();
    if (v.isEmpty) return '';
    if (v.startsWith('v') || v.startsWith('V')) {
      v = v.substring(1);
    }
    final plusIndex = v.indexOf('+');
    if (plusIndex >= 0) {
      v = v.substring(0, plusIndex);
    }
    final dashIndex = v.indexOf('-');
    if (dashIndex >= 0) {
      v = v.substring(0, dashIndex);
    }
    return v.trim();
  }

  int _compareSemver(String a, String b) {
    final aParts = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final bParts = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final maxLen = aParts.length > bParts.length
        ? aParts.length
        : bParts.length;

    for (var i = 0; i < maxLen; i++) {
      final aVal = i < aParts.length ? aParts[i] : 0;
      final bVal = i < bParts.length ? bParts[i] : 0;
      if (aVal > bVal) return 1;
      if (aVal < bVal) return -1;
    }
    return 0;
  }

  String? _pickInzxApkDownloadUrl(dynamic assetsRaw) {
    if (assetsRaw is! List) return null;

    for (final item in assetsRaw) {
      if (item is! Map<String, dynamic>) continue;
      final name = (item['name'] as String?)?.trim() ?? '';
      final url = (item['browser_download_url'] as String?)?.trim() ?? '';
      if (name.toLowerCase() == 'inzx.apk' && url.isNotEmpty) {
        return url;
      }
    }

    return null;
  }
}
