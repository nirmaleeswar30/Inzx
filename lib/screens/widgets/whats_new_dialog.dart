import '../../core/utils/open_once.dart';
import 'dart:ui';
import 'package:material_ui/material_ui.dart';
import 'package:iconsax/iconsax.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/github_release_update_service.dart';

class WhatsNewDialog {
  static Future<void> show(
    BuildContext context, {
    GithubReleaseInfo? releaseInfo,
    String? currentVersion,
  }) async {
    final info = releaseInfo ??
        await GithubReleaseUpdateService.instance.fetchLatestReleaseInfo();
    final pkgInfo = await PackageInfo.fromPlatform();
    final version = currentVersion ?? pkgInfo.version;

    if (!context.mounted) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final primaryColor = colorScheme.primary;

    final rawBody = info?.body?.trim();
    final bodyText = (rawBody != null && rawBody.isNotEmpty)
        ? rawBody
        : 'No release notes available.';

    await openOnce('WhatsNewDialog', () => showDialog(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                constraints: const BoxConstraints(maxHeight: 520),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E1E1E).withValues(alpha: 0.92)
                      : Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: primaryColor.withValues(alpha: 0.35),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: primaryColor.withValues(alpha: 0.25),
                      blurRadius: 30,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.asset(
                            isDark ? 'assets/icon/logo_dark.png' : 'assets/icon/logo_light.png',
                            width: 52,
                            height: 52,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Icon(
                              Iconsax.note_2,
                              size: 40,
                              color: primaryColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'What\'s New in Inzx',
                                style: TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Version v${version.replaceAll('v', '').replaceAll('V', '')}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: primaryColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Divider(
                      color: isDark ? Colors.white12 : Colors.black12,
                      height: 1,
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: MarkdownBody(
                            data: bodyText,
                            selectable: true,
                            onTapLink: (text, href, title) async {
                              if (href != null && href.isNotEmpty) {
                                final uri = Uri.tryParse(href);
                                if (uri != null) {
                                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                                }
                              }
                            },
                            styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                              p: TextStyle(
                                fontSize: 13.5,
                                height: 1.55,
                                color: isDark ? Colors.white70 : Colors.black87,
                              ),
                              h1: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                              h2: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                              h3: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: primaryColor,
                              ),
                              listBullet: TextStyle(
                                fontSize: 13.5,
                                color: primaryColor,
                              ),
                              code: TextStyle(
                                fontSize: 12.5,
                                backgroundColor: isDark ? Colors.white10 : Colors.black12,
                                color: primaryColor,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          flex: 4,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: primaryColor,
                              side: BorderSide(
                                color: primaryColor.withValues(alpha: 0.4),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: () async {
                              final uri = Uri.parse('https://github.com/sponsors/nirmaleeswar30');
                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                            },
                            icon: const Icon(Iconsax.heart, size: 18),
                            label: const Text(
                              'Donate',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 6,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: primaryColor,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: () => Navigator.pop(dialogContext),
                            child: const Text(
                              'Got it!',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ));
  }
}
