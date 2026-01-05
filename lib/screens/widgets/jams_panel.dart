import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:marquee/marquee.dart';
import '../../providers/providers.dart';
import '../../providers/jams_provider.dart';
import '../../services/jams/jams_models.dart';

/// Jams panel shown as a bottom sheet from Now Playing
class JamsPanel extends ConsumerStatefulWidget {
  final Color backgroundColor;
  final Color textColor;
  final Color accentColor;

  const JamsPanel({
    super.key,
    required this.backgroundColor,
    required this.textColor,
    required this.accentColor,
  });

  static void show(
    BuildContext context, {
    required Color backgroundColor,
    required Color textColor,
    required Color accentColor,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => JamsPanel(
        backgroundColor: backgroundColor,
        textColor: textColor,
        accentColor: accentColor,
      ),
    );
  }

  @override
  ConsumerState<JamsPanel> createState() => _JamsPanelState();
}

class _JamsPanelState extends ConsumerState<JamsPanel> {
  final _codeController = TextEditingController();
  bool _isJoining = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final googleAuth = ref.watch(googleAuthStateProvider);
    final session = ref.watch(currentJamSessionProvider).valueOrNull;
    final jamsState = ref.watch(jamsNotifierProvider);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: widget.backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: widget.textColor.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(
                  Iconsax.profile_2user,
                  color: widget.accentColor,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(
                  'Jams',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: widget.textColor,
                  ),
                ),
                const Spacer(),
                if (session != null)
                  IconButton(
                    onPressed: () {
                      ref.read(jamsNotifierProvider.notifier).leaveSession();
                      Navigator.pop(context);
                    },
                    icon: Icon(Iconsax.logout, color: Colors.red.shade400),
                  ),
              ],
            ),
          ),

          // Content
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: googleAuth.isSignedIn
                  ? (session != null
                        ? _buildActiveSession(session)
                        : _buildNoSession(jamsState))
                  : _buildSignInPrompt(),
            ),
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  /// Prompt to sign in with Google
  Widget _buildSignInPrompt() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(
            Iconsax.user_cirlce_add,
            size: 64,
            color: widget.textColor.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            'Sign in to use Jams',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: widget.textColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Listen together with friends in real-time',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: widget.textColor.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () async {
              await ref.read(googleAuthStateProvider.notifier).signIn();
            },
            icon: const Icon(Icons.login),
            label: const Text('Sign in with Google'),
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.accentColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  /// No active session - show create/join options
  Widget _buildNoSession(JamsUIState state) {
    return Column(
      children: [
        // Illustration
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: widget.accentColor.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Iconsax.music_playlist,
            size: 48,
            color: widget.accentColor,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Listen together',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: widget.textColor,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Start a Jam to share music with friends.\nEveryone hears the same song in sync.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: widget.textColor.withValues(alpha: 0.6),
            height: 1.4,
          ),
        ),
        const SizedBox(height: 32),

        // Start a Jam button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: state.isLoading ? null : _startJam,
            icon: state.isLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Iconsax.add),
            label: Text(state.isLoading ? 'Starting...' : 'Start a Jam'),
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.accentColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Divider
        Row(
          children: [
            Expanded(child: Divider(color: widget.textColor.withValues(alpha: 0.2))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'or',
                style: TextStyle(color: widget.textColor.withValues(alpha: 0.5)),
              ),
            ),
            Expanded(child: Divider(color: widget.textColor.withValues(alpha: 0.2))),
          ],
        ),
        const SizedBox(height: 16),

        // Join with code
        Text(
          'Join a friend\'s Jam',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: widget.textColor.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _codeController,
                textCapitalization: TextCapitalization.characters,
                maxLength: 6,
                style: TextStyle(
                  color: widget.textColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 4,
                ),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  hintText: 'CODE',
                  hintStyle: TextStyle(
                    color: widget.textColor.withValues(alpha: 0.3),
                    letterSpacing: 4,
                  ),
                  counterText: '',
                  filled: true,
                  fillColor: widget.textColor.withValues(alpha: 0.1),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: _isJoining ? null : _joinJam,
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.textColor.withValues(alpha: 0.1),
                foregroundColor: widget.textColor,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isJoining
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: widget.textColor,
                      ),
                    )
                  : const Text('Join'),
            ),
          ],
        ),

        // Error message
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              state.error!,
              style: TextStyle(color: Colors.red.shade400, fontSize: 13),
            ),
          ),

        const SizedBox(height: 20),
      ],
    );
  }

  /// Active session view
  Widget _buildActiveSession(JamSession session) {
    final isHost = ref.watch(isJamHostProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Session code card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: widget.accentColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: widget.accentColor.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              Text(
                'Share this code',
                style: TextStyle(
                  fontSize: 13,
                  color: widget.textColor.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    session.sessionCode,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: widget.accentColor,
                      letterSpacing: 8,
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: session.sessionCode),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Code copied!'),
                          backgroundColor: widget.accentColor,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                    icon: Icon(Iconsax.copy, color: widget.accentColor),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Participants
        Text(
          'Listening together (${session.participantCount})',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: widget.textColor,
          ),
        ),
        const SizedBox(height: 12),
        ...session.participants.map((p) => _buildParticipantTile(p)),
        const SizedBox(height: 24),

        // Now playing in Jam
        if (session.playbackState.currentTrack != null) ...[
          Text(
            'Now Playing',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: widget.textColor,
            ),
          ),
          const SizedBox(height: 12),
          _buildCurrentTrackCard(session.playbackState.currentTrack!),
        ],

        // Host indicator
        if (isHost)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Row(
              children: [
                Icon(Iconsax.crown1, color: Colors.amber, size: 18),
                const SizedBox(width: 8),
                Text(
                  'You\'re the host - your playback controls the Jam',
                  style: TextStyle(
                    fontSize: 12,
                    color: widget.textColor.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildParticipantTile(JamParticipant participant) {
    final isHost = ref.watch(isJamHostProvider);
    final jamsService = ref.watch(jamsServiceProvider);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.accentColor.withValues(alpha: 0.2),
            ),
            child: participant.photoUrl != null
                ? ClipOval(
                    child: CachedNetworkImage(
                      imageUrl: participant.photoUrl!,
                      fit: BoxFit.cover,
                    ),
                  )
                : Center(
                    child: Text(
                      participant.name.isNotEmpty
                          ? participant.name[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                        color: widget.accentColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          // Name
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      participant.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: widget.textColor,
                      ),
                    ),
                    if (participant.isHost) ...[
                      const SizedBox(width: 6),
                      Icon(Iconsax.crown1, color: Colors.amber, size: 14),
                    ],
                    if (!participant.isHost &&
                        participant.canControlPlayback) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Iconsax.play_circle,
                        color: widget.accentColor,
                        size: 14,
                      ),
                    ],
                  ],
                ),
                Text(
                  participant.isHost
                      ? 'Host'
                      : (participant.canControlPlayback
                            ? 'Can control'
                            : 'Listening'),
                  style: TextStyle(
                    fontSize: 12,
                    color: widget.textColor.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          // Host controls for this participant
          if (isHost && !participant.isHost)
            PopupMenuButton<String>(
              icon: Icon(
                Iconsax.more,
                color: widget.textColor.withValues(alpha: 0.5),
                size: 20,
              ),
              color: widget.backgroundColor,
              onSelected: (value) async {
                switch (value) {
                  case 'toggle_control':
                    await jamsService?.setParticipantPermission(
                      participant.id,
                      !participant.canControlPlayback,
                    );
                    break;
                  case 'make_host':
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: widget.backgroundColor,
                        title: Text(
                          'Transfer Host?',
                          style: TextStyle(color: widget.textColor),
                        ),
                        content: Text(
                          'Make ${participant.name} the new host? You will lose host controls.',
                          style: TextStyle(
                            color: widget.textColor.withValues(alpha: 0.7),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text(
                              'Cancel',
                              style: TextStyle(
                                color: widget.textColor.withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: Text(
                              'Transfer',
                              style: TextStyle(color: widget.accentColor),
                            ),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await ref
                          .read(jamsNotifierProvider.notifier)
                          .transferHost(participant.id);
                    }
                    break;
                }
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  value: 'toggle_control',
                  child: Row(
                    children: [
                      Icon(
                        participant.canControlPlayback
                            ? Iconsax.close_circle
                            : Iconsax.play_circle,
                        color: widget.textColor,
                        size: 18,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        participant.canControlPlayback
                            ? 'Remove control'
                            : 'Allow control',
                        style: TextStyle(color: widget.textColor),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'make_host',
                  child: Row(
                    children: [
                      Icon(Iconsax.crown1, color: Colors.amber, size: 18),
                      const SizedBox(width: 12),
                      Text(
                        'Make host',
                        style: TextStyle(color: widget.textColor),
                      ),
                    ],
                  ),
                ),
              ],
            )
          else
            // Listening indicator for non-hosts
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Live',
                    style: TextStyle(
                      color: Colors.green,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCurrentTrackCard(JamTrack track) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: widget.textColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: track.thumbnailUrl != null
                ? CachedNetworkImage(
                    imageUrl: track.thumbnailUrl!,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                  )
                : Container(
                    width: 48,
                    height: 48,
                    color: widget.accentColor.withValues(alpha: 0.3),
                    child: Icon(Iconsax.music, color: widget.accentColor),
                  ),
          ),
          const SizedBox(width: 12),
          // Track info with marquee for long text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Title with marquee
                SizedBox(
                  height: 18,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final textPainter = TextPainter(
                        text: TextSpan(
                          text: track.title,
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                            color: widget.textColor,
                          ),
                        ),
                        maxLines: 1,
                        textDirection: TextDirection.ltr,
                      )..layout();

                      if (textPainter.width > constraints.maxWidth) {
                        return Marquee(
                          text: track.title,
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                            color: widget.textColor,
                          ),
                          scrollAxis: Axis.horizontal,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          blankSpace: 40.0,
                          velocity: 25.0,
                          pauseAfterRound: const Duration(seconds: 2),
                          startPadding: 0.0,
                        );
                      }
                      return Text(
                        track.title,
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                          color: widget.textColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 2),
                // Artist with marquee
                SizedBox(
                  height: 16,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final textPainter = TextPainter(
                        text: TextSpan(
                          text: track.artist,
                          style: TextStyle(
                            fontSize: 12,
                            color: widget.textColor.withValues(alpha: 0.6),
                          ),
                        ),
                        maxLines: 1,
                        textDirection: TextDirection.ltr,
                      )..layout();

                      if (textPainter.width > constraints.maxWidth) {
                        return Marquee(
                          text: track.artist,
                          style: TextStyle(
                            fontSize: 12,
                            color: widget.textColor.withValues(alpha: 0.6),
                          ),
                          scrollAxis: Axis.horizontal,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          blankSpace: 40.0,
                          velocity: 25.0,
                          pauseAfterRound: const Duration(seconds: 2),
                          startPadding: 0.0,
                        );
                      }
                      return Text(
                        track.artist,
                        style: TextStyle(
                          fontSize: 12,
                          color: widget.textColor.withValues(alpha: 0.6),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          // Playing animation
          _buildPlayingAnimation(),
        ],
      ),
    );
  }

  Widget _buildPlayingAnimation() {
    return SizedBox(
      width: 20,
      height: 16,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(3, (i) {
          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.3, end: 1.0),
            duration: Duration(milliseconds: 300 + i * 100),
            curve: Curves.easeInOut,
            builder: (context, value, child) {
              return Container(
                width: 4,
                height: 16 * value,
                decoration: BoxDecoration(
                  color: widget.accentColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            },
          );
        }),
      ),
    );
  }

  Future<void> _startJam() async {
    final code = await ref.read(jamsNotifierProvider.notifier).createSession();
    if (code != null) {
      // Success - the session will be shown via the provider
    }
  }

  Future<void> _joinJam() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.length != 6) {
      ref.read(jamsNotifierProvider.notifier);
      return;
    }

    setState(() => _isJoining = true);
    final success = await ref
        .read(jamsNotifierProvider.notifier)
        .joinSession(code);
    setState(() => _isJoining = false);

    if (success) {
      _codeController.clear();
    }
  }
}
