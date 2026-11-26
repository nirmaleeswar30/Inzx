import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/providers/theme_provider.dart';
import '../core/utils/platform_utils.dart';
import '../providers/providers.dart';
import 'ytmusic_login_screen.dart';

class PlaylistTransferScreen extends StatelessWidget {
  const PlaylistTransferScreen({super.key});

  static const title = 'Transfer playlists from other apps';
  static const subtitle = 'Bring playlists into your YouTube Music library';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: desktopPageBackground(
        Theme.of(context).scaffoldBackgroundColor,
      ),
      appBar: AppBar(backgroundColor: Colors.transparent),
      body: const SafeArea(top: false, child: PlaylistTransferPage()),
    );
  }
}

/// The same transfer options are available from Settings and onboarding.
class PlaylistTransferPage extends ConsumerStatefulWidget {
  const PlaylistTransferPage({super.key, this.footer});

  final Widget? footer;

  @override
  ConsumerState<PlaylistTransferPage> createState() =>
      _PlaylistTransferPageState();
}

class _PlaylistTransferPageState extends ConsumerState<PlaylistTransferPage> {
  // These are the destination-specific links in YouTube Music Help.
  static final _tuneMyMusic = Uri.https('www.tunemymusic.com', '/transfer', {
    'mode': 'youtubemusic',
  });
  static final _soundiiz = Uri.https('soundiiz.com', '/partner/youtube-music');

  bool _refreshing = false;

  Future<void> _openTransfer(Uri uri) async {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      // Some platforms throw when no browser can handle the link.
    }
    if (mounted) _showMessage('Couldn’t open the transfer website.');
  }

  Future<void> _refreshPlaylists() async {
    setState(() => _refreshing = true);
    try {
      ref.invalidate(ytMusicSavedPlaylistsProvider);
      await ref.read(ytMusicSavedPlaylistsProvider.future);
      if (mounted) _showMessage('Check Playlists in your Library.');
    } catch (_) {
      if (mounted) _showMessage('Couldn’t refresh playlists. Try again.');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(ytMusicAuthStateProvider);
    final theme = Theme.of(context);
    final red = getAccentColor(InzxAccentColor.red);
    final accent = theme.brightness == Brightness.dark
        ? Color.lerp(red, Colors.white, 0.5)!
        : red;
    final transferButtonStyle = FilledButton.styleFrom(
      backgroundColor: red,
      foregroundColor: Colors.white,
    );
    final linkStyle = TextButton.styleFrom(foregroundColor: accent);

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _TransferIllustration(accent: accent),
                    const SizedBox(height: 16),
                    Text(
                      PlaylistTransferScreen.title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Copy your playlists to YouTube Music using the same '
                      'Google account and YouTube channel you use in Inzx.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        FilledButton.icon(
                          style: transferButtonStyle,
                          onPressed: () => _openTransfer(_tuneMyMusic),
                          icon: const Icon(Icons.open_in_new_rounded, size: 16),
                          label: const Text('TuneMyMusic'),
                        ),
                        FilledButton.icon(
                          style: transferButtonStyle,
                          onPressed: () => _openTransfer(_soundiiz),
                          icon: const Icon(Icons.open_in_new_rounded, size: 16),
                          label: const Text('Soundiiz'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (auth.isLoggedIn) ...[
                      const Text(
                        'When the transfer finishes, refresh your Inzx Library.',
                        textAlign: TextAlign.center,
                      ),
                      TextButton(
                        style: linkStyle,
                        onPressed: _refreshing ? null : _refreshPlaylists,
                        child: Text(
                          _refreshing ? 'Refreshing…' : 'Refresh playlists',
                        ),
                      ),
                    ] else if (!auth.isLoading)
                      TextButton(
                        style: linkStyle,
                        onPressed: () => openSignIn(context),
                        child: const Text(
                          'Sign in to Inzx to see your playlists',
                        ),
                      ),
                    if (widget.footer case final footer?) ...[
                      const SizedBox(height: 20),
                      footer,
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TransferIllustration extends StatelessWidget {
  const _TransferIllustration({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.78),
              border: Border.all(color: accent.withValues(alpha: 0.32)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('Other apps', style: theme.textTheme.labelLarge),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Icon(Icons.arrow_forward_rounded, color: accent, size: 28),
        ),
        Image.asset(
          'assets/logo_transparent.png',
          width: 88,
          height: 88,
          cacheWidth: 264,
          semanticLabel: 'Inzx',
        ),
      ],
    );
  }
}
