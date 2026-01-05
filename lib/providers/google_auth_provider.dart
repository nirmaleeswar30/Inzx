import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/auth/google_auth_service.dart';

/// Google Auth Service provider (singleton)
final googleAuthServiceProvider = Provider<GoogleAuthService>((ref) {
  return GoogleAuthService();
});

/// Google Auth State
class GoogleAuthState {
  final bool isSignedIn;
  final bool isLoading;
  final GoogleUserProfile? user;
  final String? error;

  const GoogleAuthState({
    this.isSignedIn = false,
    this.isLoading = true,
    this.user,
    this.error,
  });

  GoogleAuthState copyWith({
    bool? isSignedIn,
    bool? isLoading,
    GoogleUserProfile? user,
    String? error,
    bool clearUser = false,
  }) {
    return GoogleAuthState(
      isSignedIn: isSignedIn ?? this.isSignedIn,
      isLoading: isLoading ?? this.isLoading,
      user: clearUser ? null : (user ?? this.user),
      error: error,
    );
  }
}

/// Google Auth State Notifier
class GoogleAuthNotifier extends StateNotifier<GoogleAuthState> {
  final GoogleAuthService _authService;

  GoogleAuthNotifier(this._authService) : super(const GoogleAuthState()) {
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final success = await _authService.initialize();
      state = GoogleAuthState(
        isSignedIn: success,
        isLoading: false,
        user: _authService.currentUser,
      );
      if (success) {
        if (kDebugMode) {
          print(
            'GoogleAuth: Initialized with user: ${_authService.currentUser?.displayName}',
          );
        }
      }
    } catch (e) {
      state = GoogleAuthState(
        isSignedIn: false,
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Sign in with Google
  Future<bool> signIn() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final user = await _authService.signIn();
      if (user != null) {
        state = GoogleAuthState(isSignedIn: true, isLoading: false, user: user);
        return true;
      } else {
        state = state.copyWith(
          isLoading: false,
          error: 'Sign-in was cancelled',
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  /// Sign out
  Future<void> signOut() async {
    state = state.copyWith(isLoading: true);
    await _authService.signOut();
    state = const GoogleAuthState(isSignedIn: false, isLoading: false);
  }
}

/// Google Auth State Provider
final googleAuthStateProvider =
    StateNotifierProvider<GoogleAuthNotifier, GoogleAuthState>((ref) {
      final authService = ref.watch(googleAuthServiceProvider);
      return GoogleAuthNotifier(authService);
    });

/// Convenience provider for just the user profile
final googleUserProfileProvider = Provider<GoogleUserProfile?>((ref) {
  return ref.watch(googleAuthStateProvider).user;
});

/// Convenience provider for checking if signed in
final isGoogleSignedInProvider = Provider<bool>((ref) {
  return ref.watch(googleAuthStateProvider).isSignedIn;
});
