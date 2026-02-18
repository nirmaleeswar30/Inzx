import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:iconsax/iconsax.dart';
import '../providers/providers.dart';
import '../services/jams/jams_models.dart';
import '../core/design_system/colors.dart';

/// Jams screen - create or join collaborative listening sessions
class JamsScreen extends ConsumerStatefulWidget {
  const JamsScreen({super.key});

  static void open(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const JamsScreen()));
  }

  @override
  ConsumerState<JamsScreen> createState() => _JamsScreenState();
}

class _JamsScreenState extends ConsumerState<JamsScreen> {
  final _codeController = TextEditingController();
  bool _isJoining = false;

  @override
  void initState() {
    super.initState();
    // Listen to text changes to update button state
    _codeController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final googleAuth = ref.watch(googleAuthStateProvider);
    final currentSession = ref.watch(currentJamSessionProvider).valueOrNull;
    final jamsUIState = ref.watch(jamsNotifierProvider);
    final connectionState = ref.watch(jamsConnectionStateProvider).valueOrNull;
    final albumColors = ref.watch(albumColorsProvider);

    // Use dynamic colors if available, but respect light/dark mode
    final hasAlbumColors = !albumColors.isDefault;
    final Color backgroundColor;
    final Color textColor;

    if (hasAlbumColors && isDark) {
      backgroundColor = albumColors.backgroundPrimary;
      textColor = albumColors.onBackground;
    } else {
      backgroundColor = isDark ? Colors.black : Colors.grey.shade50;
      textColor = isDark ? Colors.white : Colors.black;
    }

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        elevation: 0,
        title: Text(
          'Jams',
          style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: googleAuth.isSignedIn
          ? currentSession != null
                ? _buildActiveSession(
                    isDark,
                    currentSession,
                    albumColors,
                    connectionState,
                  )
                : _buildJoinOrCreate(isDark, jamsUIState, albumColors)
          : _buildSignInPrompt(isDark, albumColors),
    );
  }

  /// Prompt to sign in with Google
  Widget _buildSignInPrompt(bool isDark, AlbumColors albumColors) {
    final hasAlbumColors = !albumColors.isDefault;
    // Respect light/dark mode for text colors
    final textColor = isDark
        ? (hasAlbumColors ? albumColors.onBackground : Colors.white)
        : Colors.black;
    final secondaryColor = textColor.withValues(alpha: 0.7);
    final accentColor = hasAlbumColors ? albumColors.accent : Colors.purple;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(Iconsax.music_playlist, color: accentColor, size: 50),
            ),
            const SizedBox(height: 24),
            Text(
              'Listen Together',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Sign in with Google to start or join a Jam session with friends',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: secondaryColor),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () async {
                await ref.read(googleAuthStateProvider.notifier).signIn();
              },
              icon: const Icon(Icons.login),
              label: const Text('Sign in with Google'),
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: MineColors.contrastTextOn(accentColor),
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Join or create session UI
  Widget _buildJoinOrCreate(
    bool isDark,
    JamsUIState uiState,
    AlbumColors albumColors,
  ) {
    final hasAlbumColors = !albumColors.isDefault;
    // Respect light/dark mode for text colors
    final textColor = isDark
        ? (hasAlbumColors ? albumColors.onBackground : Colors.white)
        : Colors.black;
    final secondaryColor = textColor.withValues(alpha: 0.7);
    final accentColor = hasAlbumColors ? albumColors.accent : Colors.purple;
    final surfaceColor = hasAlbumColors
        ? albumColors.surface.withValues(alpha: isDark ? 0.5 : 0.15)
        : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header illustration
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Iconsax.profile_2user, size: 64, color: accentColor),
                const SizedBox(height: 16),
                Text(
                  'Listen with friends in sync',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
                Text(
                  'Same song, same moment',
                  style: TextStyle(color: secondaryColor),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Start a Jam button
          _buildActionCard(
            isDark: isDark,
            icon: Iconsax.add_circle,
            iconColor: accentColor,
            title: 'Start a Jam',
            subtitle: 'Create a session and invite friends',
            onTap: uiState.isLoading ? null : _createSession,
            isLoading: uiState.isLoading && !_isJoining,
            albumColors: albumColors,
          ),

          const SizedBox(height: 16),

          // Join a Jam section
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: textColor.withValues(alpha: 0.1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Iconsax.login, color: accentColor),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Join a Jam',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: textColor,
                            ),
                          ),
                          Text(
                            'Enter the 6-digit code',
                            style: TextStyle(
                              fontSize: 13,
                              color: secondaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _codeController,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 6,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 8,
                    color: textColor,
                  ),
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: 'ABC123',
                    hintStyle: TextStyle(
                      color: textColor.withValues(alpha: 0.3),
                      letterSpacing: 8,
                    ),
                    filled: true,
                    fillColor: textColor.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                    UpperCaseTextFormatter(),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed:
                        uiState.isLoading || _codeController.text.length < 6
                        ? null
                        : _joinSession,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      disabledBackgroundColor: accentColor.withValues(
                        alpha: 0.3,
                      ),
                      foregroundColor: MineColors.contrastTextOn(accentColor),
                      disabledForegroundColor: MineColors.contrastTextOn(
                        accentColor,
                      ).withValues(alpha: 0.5),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: uiState.isLoading && _isJoining
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: MineColors.contrastTextOn(accentColor),
                            ),
                          )
                        : const Text('Join'),
                  ),
                ),
              ],
            ),
          ),

          // Error message
          if (uiState.error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      uiState.error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionCard({
    required bool isDark,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    bool isLoading = false,
    AlbumColors? albumColors,
  }) {
    final hasAlbumColors = albumColors != null && !albumColors.isDefault;
    // Respect light/dark mode
    final textColor = isDark
        ? (hasAlbumColors ? albumColors.onBackground : Colors.white)
        : Colors.black;
    final secondaryColor = textColor.withValues(alpha: 0.7);
    final surfaceColor = hasAlbumColors
        ? albumColors.surface.withValues(alpha: isDark ? 0.5 : 0.15)
        : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white);

    return Material(
      color: surfaceColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: textColor.withValues(alpha: 0.1)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: isLoading
                    ? Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: iconColor,
                          ),
                        ),
                      )
                    : Icon(icon, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 13, color: secondaryColor),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: secondaryColor),
            ],
          ),
        ),
      ),
    );
  }

  /// Active session UI
  Widget _buildActiveSession(
    bool isDark,
    JamSession session,
    AlbumColors albumColors,
    JamConnectionState? connectionState,
  ) {
    final isHost = ref.watch(isJamHostProvider);
    final hasAlbumColors = !albumColors.isDefault;
    // Respect light/dark mode
    final textColor = isDark
        ? (hasAlbumColors ? albumColors.onBackground : Colors.white)
        : Colors.black;
    final secondaryColor = textColor.withValues(alpha: 0.7);
    final accentColor = hasAlbumColors ? albumColors.accent : Colors.purple;

    return SafeArea(
      child: Column(
        children: [
          // Session header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  accentColor.withValues(alpha: 0.2),
                  Colors.transparent,
                ],
              ),
            ),
            child: Column(
              children: [
                // Session code
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: textColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        session.sessionCode,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 6,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: session.sessionCode),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Code copied!')),
                          );
                        },
                        icon: Icon(Icons.copy, color: secondaryColor),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isHost ? 'You\'re the host' : 'Hosted by ${session.hostName}',
                  style: TextStyle(color: secondaryColor),
                ),
                if (connectionState != null) ...[
                  const SizedBox(height: 8),
                  _buildConnectionBadge(connectionState, textColor),
                ],
              ],
            ),
          ),

          // Participants
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Listening Together (${session.participants.length})',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 76,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: session.participants.length,
                    itemBuilder: (context, index) {
                      final participant = session.participants[index];
                      return Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Stack(
                              children: [
                                Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: participant.photoUrl == null
                                        ? accentColor.withValues(alpha: 0.5)
                                        : null,
                                    border: participant.isHost
                                        ? Border.all(
                                            color: Colors.amber,
                                            width: 2,
                                          )
                                        : null,
                                  ),
                                  child: ClipOval(
                                    child: participant.photoUrl != null
                                        ? CachedNetworkImage(
                                            imageUrl: participant.photoUrl!,
                                            fit: BoxFit.cover,
                                          )
                                        : Center(
                                            child: Text(
                                              participant.name[0].toUpperCase(),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                  ),
                                ),
                                if (participant.isHost)
                                  Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: const BoxDecoration(
                                        color: Colors.amber,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.star,
                                        size: 12,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              participant.name.split(' ').first,
                              style: TextStyle(
                                fontSize: 12,
                                color: secondaryColor,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Jam Queue section (includes now playing at top)
          _buildJamQueue(isDark, session, albumColors),

          // Leave button
          Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  ref.read(jamsNotifierProvider.notifier).leaveSession();
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(isHost ? 'End Session' : 'Leave Session'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionBadge(JamConnectionState state, Color textColor) {
    final (icon, label, bg, fg) = _connectionUi(state, textColor);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  (IconData, String, Color, Color) _connectionUi(
    JamConnectionState state,
    Color fallbackText,
  ) {
    switch (state.status) {
      case JamConnectionStatus.connected:
        return (
          Icons.wifi_rounded,
          'Connected',
          Colors.green.withValues(alpha: 0.14),
          Colors.green.shade400,
        );
      case JamConnectionStatus.reconnecting:
        final suffix = state.nextRetrySeconds > 0
            ? 'Retry in ${state.nextRetrySeconds}s'
            : 'Reconnecting';
        final label = state.attempt > 0
            ? 'Reconnecting (${state.attempt}) · $suffix'
            : 'Reconnecting · $suffix';
        return (
          Icons.sync,
          label,
          Colors.orange.withValues(alpha: 0.15),
          Colors.orange.shade300,
        );
      case JamConnectionStatus.disconnected:
        return (
          Icons.wifi_off_rounded,
          'Disconnected',
          Colors.red.withValues(alpha: 0.14),
          fallbackText.withValues(alpha: 0.9),
        );
    }
  }

  Widget _buildJamQueue(
    bool isDark,
    JamSession session,
    AlbumColors albumColors,
  ) {
    final canControlPlayback = ref.watch(canControlJamPlaybackProvider);
    final jamsService = ref.watch(jamsServiceProvider);
    final hasAlbumColors = !albumColors.isDefault;
    // Respect light/dark mode
    final textColor = isDark
        ? (hasAlbumColors ? albumColors.onBackground : Colors.white)
        : Colors.black;
    final secondaryColor = textColor.withValues(alpha: 0.7);
    final surfaceColor = hasAlbumColors
        ? albumColors.surface.withValues(alpha: isDark ? 0.3 : 0.1)
        : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white);
    final accentColor = hasAlbumColors ? albumColors.accent : Colors.purple;

    final queue = session.queue;
    final currentTrack = session.playbackState.currentTrack;
    final isPlaying = session.playbackState.isPlaying;

    // Find participant names from session
    String getAddedByName(String oderId) {
      final participant = session.participants
          .where((p) => p.id == oderId)
          .firstOrNull;
      return participant?.name ?? 'Someone';
    }

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Playing',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
                Icon(Iconsax.music_playlist, size: 20, color: secondaryColor),
              ],
            ),
            const SizedBox(height: 12),

            // Currently playing track at the top
            if (currentTrack != null)
              GestureDetector(
                onTap: canControlPlayback
                    ? () {
                        final audioPlayer = ref.read(
                          audioPlayerServiceProvider,
                        );
                        if (isPlaying) {
                          audioPlayer.pause();
                        } else {
                          audioPlayer.play();
                        }
                      }
                    : null,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: currentTrack.thumbnailUrl != null
                          ? CachedNetworkImage(
                              imageUrl: currentTrack.thumbnailUrl!,
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              width: 48,
                              height: 48,
                              color: Colors.grey,
                              child: const Icon(
                                Icons.music_note,
                                color: Colors.white,
                              ),
                            ),
                    ),
                    title: Text(
                      currentTrack.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      currentTrack.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: secondaryColor, fontSize: 12),
                    ),
                    trailing: Icon(
                      isPlaying ? Iconsax.pause : Iconsax.play,
                      color: accentColor,
                    ),
                  ),
                ),
              ),

            // Queue header
            if (queue.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Up Next (${queue.length})',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: secondaryColor,
                  ),
                ),
              ),

            Expanded(
              child: queue.isEmpty && currentTrack == null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Iconsax.music, size: 40, color: secondaryColor),
                          const SizedBox(height: 12),
                          Text(
                            'No tracks in queue',
                            style: TextStyle(color: secondaryColor),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Add songs to play them together',
                            style: TextStyle(
                              color: secondaryColor.withValues(alpha: 0.7),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    )
                  : queue.isEmpty
                  ? Center(
                      child: Text(
                        'Queue is empty',
                        style: TextStyle(color: secondaryColor),
                      ),
                    )
                  : ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      itemCount: queue.length,
                      itemBuilder: (context, index) {
                        final item = queue[index];
                        final track = item.track;
                        final addedByName = getAddedByName(item.addedBy);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: surfaceColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
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
                                      color: Colors.grey,
                                      child: const Icon(
                                        Icons.music_note,
                                        color: Colors.white,
                                      ),
                                    ),
                            ),
                            title: Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: textColor),
                            ),
                            subtitle: Text(
                              '${track.artist} • Added by $addedByName',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: secondaryColor,
                                fontSize: 12,
                              ),
                            ),
                            trailing: canControlPlayback
                                ? IconButton(
                                    icon: Icon(
                                      Iconsax.trash,
                                      size: 20,
                                      color: secondaryColor,
                                    ),
                                    onPressed: () {
                                      jamsService?.removeFromQueue(index);
                                    },
                                  )
                                : null,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createSession() async {
    setState(() => _isJoining = false);
    final code = await ref.read(jamsNotifierProvider.notifier).createSession();
    if (!mounted) return;
    if (code != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Session created! Code: $code')));
    }
  }

  Future<void> _joinSession() async {
    setState(() => _isJoining = true);
    final success = await ref
        .read(jamsNotifierProvider.notifier)
        .joinSession(_codeController.text.toUpperCase());
    if (!mounted) return;
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not join session. Check the code.'),
        ),
      );
    }
  }
}

/// Formatter to convert text to uppercase
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
