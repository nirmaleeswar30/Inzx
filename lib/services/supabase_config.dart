import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Supabase configuration and initialization
class SupabaseConfig {
  // Supabase project credentials for Jams feature
  static String get supabaseUrl => dotenv.env['SUPABASE_URL'] ?? '';
  static String get supabaseAnonKey => dotenv.env['SUPABASE_ANON_KEY'] ?? '';

  static bool _initialized = false;

  /// Initialize Supabase (call once at app startup)
  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      await Supabase.initialize(
        url: supabaseUrl,
        anonKey: supabaseAnonKey,
        // No auth needed for Jams - we use anonymous realtime
        authOptions: const FlutterAuthClientOptions(
          authFlowType: AuthFlowType.implicit,
        ),
        realtimeClientOptions: const RealtimeClientOptions(eventsPerSecond: 10),
      );
      _initialized = true;
      if (kDebugMode) {
        print('SupabaseConfig: Initialized successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        print('SupabaseConfig: Initialization failed: $e');
      }
    }
  }

  /// Check if Supabase is available
  static bool get isAvailable =>
      _initialized &&
      supabaseUrl.isNotEmpty &&
      supabaseUrl != 'YOUR_SUPABASE_URL';

  /// Get Supabase client (throws if not initialized)
  static SupabaseClient get client {
    if (!_initialized) {
      throw Exception(
        'Supabase not initialized. Call SupabaseConfig.initialize() first.',
      );
    }
    return Supabase.instance.client;
  }
}
