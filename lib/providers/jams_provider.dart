import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/jams/jams_service_supabase.dart';
import '../services/jams/jams_models.dart';
import '../services/jams/jams_sync_controller.dart';
import '../services/audio_player_service.dart';
import '../services/supabase_config.dart';
import 'google_auth_provider.dart';

/// Check if Jams feature is available (Supabase configured + user signed in)
final isJamsAvailableProvider = Provider<bool>((ref) {
  final googleAuth = ref.watch(googleAuthStateProvider);
  return SupabaseConfig.isAvailable && googleAuth.isSignedIn;
});

/// Jams service provider - requires Google auth and Supabase
/// Uses keepAlive to maintain the same instance across screens
final jamsServiceProvider = Provider<JamsService?>((ref) {
  final googleAuth = ref.watch(googleAuthStateProvider);

  if (!googleAuth.isSignedIn || googleAuth.user == null) {
    return null; // Can't use Jams without Google sign-in
  }

  if (!SupabaseConfig.isAvailable) {
    return null; // Supabase not configured
  }

  // Keep this provider alive so the same JamsService instance is reused
  // This ensures the Realtime channel and session state persist across screens
  ref.keepAlive();

  final user = googleAuth.user!;
  final service = JamsService(
    oderId: user.id,
    userName: user.displayName ?? 'Anonymous',
    userPhotoUrl: user.photoUrl,
  );

  // Dispose the service when the provider is disposed (e.g., on logout)
  ref.onDispose(() {
    service.dispose();
  });

  return service;
});

/// Jams sync controller provider - syncs audio playback with Jams
final jamsSyncControllerProvider = Provider<JamsSyncController?>((ref) {
  final jamsService = ref.watch(jamsServiceProvider);
  if (jamsService == null) return null;

  final audioPlayer = AudioPlayerService.instance;
  return JamsSyncController(jamsService: jamsService, audioPlayer: audioPlayer);
});

/// Current Jam session (null if not in a session)
final currentJamSessionProvider = StreamProvider<JamSession?>((ref) {
  final jamsService = ref.watch(jamsServiceProvider);
  if (jamsService == null) {
    return Stream.value(null);
  }
  return jamsService.sessionStream;
});

/// Jams playback state stream
final jamsPlaybackProvider = StreamProvider<JamPlaybackState>((ref) {
  final jamsService = ref.watch(jamsServiceProvider);
  if (jamsService == null) {
    return const Stream.empty();
  }
  return jamsService.playbackStream;
});

/// Jams error stream
final jamsErrorProvider = StreamProvider<String>((ref) {
  final jamsService = ref.watch(jamsServiceProvider);
  if (jamsService == null) {
    return const Stream.empty();
  }
  return jamsService.errorStream;
});

/// Whether user is currently in a Jam session
final isInJamSessionProvider = Provider<bool>((ref) {
  final session = ref.watch(currentJamSessionProvider).valueOrNull;
  return session != null;
});

/// Whether current user is the Jam host
/// This watches the session stream so it updates when host changes
final isJamHostProvider = Provider<bool>((ref) {
  // Watch the session stream to react to host changes
  final session = ref.watch(currentJamSessionProvider).valueOrNull;
  final jamsService = ref.watch(jamsServiceProvider);

  if (jamsService == null || session == null) return false;

  // Check if current user is the host by comparing with session hostId
  return session.hostId == jamsService.oderId;
});

/// Jam queue provider - returns the queue from the current session
final jamQueueProvider = Provider<List<JamQueueItem>>((ref) {
  final session = ref.watch(currentJamSessionProvider).valueOrNull;
  return session?.queue ?? [];
});

/// Whether current user can control playback (host or has permission)
final canControlJamPlaybackProvider = Provider<bool>((ref) {
  final session = ref.watch(currentJamSessionProvider).valueOrNull;
  final jamsService = ref.watch(jamsServiceProvider);

  if (jamsService == null) return true; // Not in a session, can control
  if (session == null) return true; // No session yet

  // Host always can control
  final isHost = session.hostId == jamsService.oderId;
  if (isHost) return true;

  // Check if current user has control permission from participants list
  final me = session.participants
      .where((p) => p.id == jamsService.oderId)
      .firstOrNull;
  return me?.canControlPlayback ?? false;
});

/// Notifier for Jams UI state and actions
class JamsNotifier extends StateNotifier<JamsUIState> {
  final JamsService? _jamsService;
  final JamsSyncController? _syncController;

  JamsNotifier(this._jamsService, this._syncController)
    : super(const JamsUIState());

  /// Create a new Jam session
  Future<String?> createSession() async {
    if (_jamsService == null) {
      state = state.copyWith(error: 'Please sign in with Google first');
      return null;
    }

    state = state.copyWith(isLoading: true, error: null);

    try {
      final code = await _jamsService.createSession();
      if (code != null) {
        // Start sync as host
        _syncController?.startSync();

        // Initialize jam queue from current player queue
        await _syncController?.initializeJamQueueFromPlayer();
      }
      state = state.copyWith(isLoading: false);
      return code;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return null;
    }
  }

  /// Join a Jam session with a code
  Future<bool> joinSession(String code) async {
    if (_jamsService == null) {
      state = state.copyWith(error: 'Please sign in with Google first');
      return false;
    }

    state = state.copyWith(isLoading: true, error: null);

    try {
      final success = await _jamsService.joinSession(code);
      if (success) {
        // Start sync as participant
        if (kDebugMode) {
          print(
            'JamsNotifier: Join successful, starting sync. syncController=${_syncController != null ? "exists" : "NULL"}',
          );
        }
        _syncController?.startSync();
      }
      state = state.copyWith(isLoading: false);
      return success;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  /// Leave the current session
  void leaveSession() {
    _syncController?.stopSync();
    _jamsService?.leaveSession();
  }

  /// Transfer host to another participant (host only)
  Future<bool> transferHost(String newHostId) async {
    if (_jamsService == null) return false;
    final success = await _jamsService.transferHost(newHostId);
    if (success) {
      // Restart sync with new role
      _syncController?.stopSync();
      _syncController?.startSync();
    }
    return success;
  }

  /// Clear error
  void clearError() {
    state = state.copyWith(error: null);
  }
}

/// UI state for Jams feature
class JamsUIState {
  final bool isLoading;
  final String? error;

  const JamsUIState({this.isLoading = false, this.error});

  JamsUIState copyWith({bool? isLoading, String? error}) {
    return JamsUIState(isLoading: isLoading ?? this.isLoading, error: error);
  }
}

/// Jams UI notifier provider
final jamsNotifierProvider = StateNotifierProvider<JamsNotifier, JamsUIState>((
  ref,
) {
  final jamsService = ref.watch(jamsServiceProvider);
  final syncController = ref.watch(jamsSyncControllerProvider);
  return JamsNotifier(jamsService, syncController);
});
