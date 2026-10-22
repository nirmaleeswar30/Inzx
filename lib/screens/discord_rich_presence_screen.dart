import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/design_system/design_system.dart';
import '../providers/providers.dart';
import '../services/discord/discord_rpc_service.dart';
import 'widgets/discord_logo.dart';

/// Discord's brand blurple.
const Color _discordBlurple = Color(0xFF5865F2);

/// Dedicated screen for Discord Rich Presence — connection and display
/// preferences. Presence is connection-driven: connecting an account turns it
/// on, disconnecting turns it off (no separate master toggle).
class DiscordRichPresenceScreen extends ConsumerStatefulWidget {
  const DiscordRichPresenceScreen({super.key});

  @override
  ConsumerState<DiscordRichPresenceScreen> createState() =>
      _DiscordRichPresenceScreenState();
}

class _DiscordRichPresenceScreenState
    extends ConsumerState<DiscordRichPresenceScreen> {
  DiscordRpcService get _service => DiscordRpcService.instance;

  // ── Theme helpers (mirrors the settings screen) ───────────────────
  ColorScheme get _colors => Theme.of(context).colorScheme;
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  AlbumColors get _albumColors => ref.watch(albumColorsProvider);
  bool get _hasAlbumColors => !_albumColors.isDefault;

  Color get _backgroundColor {
    if (_hasAlbumColors && _isDark) return _albumColors.backgroundSecondary;
    return _isDark ? InzxColors.darkBackground : InzxColors.background;
  }

  Color get _accentColor =>
      _hasAlbumColors ? _albumColors.accent : _colors.primary;
  Color get _cardColor => _isDark
      ? Colors.white.withValues(alpha: 0.05)
      : Colors.white.withValues(alpha: 0.85);
  Color get _textPrimary =>
      _isDark ? InzxColors.darkTextPrimary : InzxColors.textPrimary;
  Color get _textSecondary =>
      _isDark ? InzxColors.darkTextSecondary : InzxColors.textSecondary;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        title: const Text('Discord Rich Presence'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Iconsax.arrow_left, color: _textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ValueListenableBuilder<DiscordRpcState>(
        valueListenable: _service.stateNotifier,
        builder: (context, rpcState, _) {
          final hasToken = _service.isAuthorized;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _heroCard(),
              const SizedBox(height: 16),
              _connectionCard(rpcState, hasToken),
              if (hasToken) ...[
                const SizedBox(height: 16),
                _preferencesCard(),
              ],
            ],
          );
        },
      ),
    );
  }

  // ── Hero ──────────────────────────────────────────────────────────
  Widget _heroCard() {
    return _card(
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: _discordBlurple,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(
              child: DiscordLogo(size: 26, color: Colors.white),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Discord Rich Presence',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Show the track you\'re playing on your Discord profile in '
                  'real time.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: _textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Connection ────────────────────────────────────────────────────
  Widget _connectionCard(DiscordRpcState rpcState, bool hasToken) {
    if (!hasToken) {
      return _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Connect your account',
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Link your Discord account to start sharing what you listen to. '
              'Your token is stored encrypted on this device only.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: _textSecondary,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _connect,
                icon: const DiscordLogo(size: 16, color: Colors.white),
                label: const Text('Connect Discord Account'),
                style: FilledButton.styleFrom(
                  backgroundColor: _discordBlurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Connected — show account + status + actions.
    final (statusColor, statusText, statusIcon) = _statusFor(rpcState);
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _avatar(rpcState),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rpcState.displayName,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(statusIcon, size: 13, color: statusColor),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            statusText,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: statusColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _connect,
                  icon: const Icon(Icons.sync_rounded, size: 16),
                  label: const Text('Change'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _discordBlurple,
                    side: const BorderSide(color: _discordBlurple),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _disconnect,
                  icon: const Icon(Icons.logout_rounded, size: 16),
                  label: const Text('Disconnect'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _avatar(DiscordRpcState rpcState) {
    if (rpcState.avatarUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: CachedNetworkImage(
          imageUrl: rpcState.avatarUrl!,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          errorWidget: (_, _, _) => _avatarFallback(),
        ),
      );
    }
    return _avatarFallback();
  }

  Widget _avatarFallback() => const CircleAvatar(
        radius: 20,
        backgroundColor: _discordBlurple,
        child: Icon(Icons.person, size: 22, color: Colors.white),
      );

  // ── Preferences ───────────────────────────────────────────────────
  Widget _preferencesCard() {
    return _card(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Column(
        children: [
          _prefTile(
            title: 'Clear presence when paused',
            subtitle: 'Stops showing "Listening" when music is paused',
            value: _service.clearOnPause,
            onChanged: (v) async {
              await _service.setClearOnPause(v);
              setState(() {});
            },
          ),
          _prefTile(
            title: 'Show song progress',
            subtitle: 'Displays elapsed and remaining track time',
            value: _service.showTimestamps,
            onChanged: (v) async {
              await _service.setShowTimestamps(v);
              setState(() {});
            },
          ),
          _prefTile(
            title: 'Show album cover art',
            subtitle: 'Displays high-resolution artwork on your profile',
            value: _service.showAlbumArt,
            onChanged: (v) async {
              await _service.setShowAlbumArt(v);
              setState(() {});
            },
          ),
        ],
      ),
    );
  }

  Widget _prefTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      title: Text(
        title,
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
          color: _textPrimary,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 11.5, color: _textSecondary),
      ),
      value: value,
      activeTrackColor: _discordBlurple,
      onChanged: onChanged,
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────
  (Color, String, IconData) _statusFor(DiscordRpcState rpcState) {
    switch (rpcState.status) {
      case DiscordRpcStatus.connected:
        return (const Color(0xFF57F287), 'Active — sharing now',
            Icons.check_circle_rounded);
      case DiscordRpcStatus.connecting:
        return (const Color(0xFFFEE75C), 'Connecting…', Icons.sync_rounded);
      case DiscordRpcStatus.error:
        return (
          const Color(0xFFED4245),
          rpcState.errorMessage ?? 'Connection error',
          Icons.error_outline_rounded,
        );
      case DiscordRpcStatus.disconnected:
        return (_textSecondary, 'Idle', Icons.pause_circle_outline_rounded);
    }
  }

  Future<void> _connect() async {
    if (!_service.isConfigured) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Discord isn\'t configured in this build.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    // Opens the system browser (Custom Tab) for OAuth — passkeys & every 2FA
    // method work there, unlike an embedded WebView.
    await _service.authorize();
    if (mounted) setState(() {});
  }

  Future<void> _disconnect() async {
    await _service.logout();
    if (mounted) setState(() {});
  }

  Widget _card({required Widget child, EdgeInsets? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _isDark
              ? InzxColors.darkBorder
              : (_hasAlbumColors
                  ? _accentColor.withValues(alpha: 0.15)
                  : InzxColors.border.withValues(alpha: 0.3)),
        ),
      ),
      child: child,
    );
  }
}
