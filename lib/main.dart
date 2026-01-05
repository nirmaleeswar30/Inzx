import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/design_system/design_system.dart';
import 'core/providers/theme_provider.dart';
import 'core/services/cache/hive_service.dart';
import 'services/audio_handler.dart';
import 'services/notification_service.dart';
import 'services/supabase_config.dart';
import 'providers/providers.dart';
import 'providers/repository_providers.dart';
import 'screens/music_app.dart';

InzxAudioHandler? audioHandler;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive for caching
  try {
    await HiveService.init();
    debugPrint('✅ Hive initialized successfully');
  } catch (e) {
    debugPrint('⚠️ Hive initialization failed: $e');
  }

  // Initialize Supabase for Jams feature
  try {
    await SupabaseConfig.initialize();
  } catch (e) {
    debugPrint('⚠️ Supabase initialization failed: $e');
  }

  // Initialize audio service for background playback
  try {
    audioHandler = await initAudioService();
  } catch (e) {
    debugPrint('Audio service initialization failed: $e');
  }

  // Initialize notification service for download progress
  try {
    await DownloadNotificationService.instance.initialize();
    debugPrint('✅ Notification service initialized successfully');
  } catch (e) {
    debugPrint('⚠️ Notification service initialization failed: $e');
  }

  // Set preferred orientations
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  runApp(
    ProviderScope(
      overrides: [
        if (audioHandler != null)
          audioHandlerProvider.overrideWithValue(audioHandler),
      ],
      child: const InzxApp(),
    ),
  );
}

/// The root widget of the Inzx music app
class InzxApp extends ConsumerStatefulWidget {
  const InzxApp({super.key});

  @override
  ConsumerState<InzxApp> createState() => _InzxAppState();
}

class _InzxAppState extends ConsumerState<InzxApp> {
  @override
  void initState() {
    super.initState();

    // Warm cache on startup (background task)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cacheWarmer = ref.read(cacheWarmingServiceProvider);
      cacheWarmer.warmCache(preTrendingMusic: true, prelikedSongs: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);

    // Get accent color
    final accentColorEnum = ref.watch(accentColorProvider);
    final lightAccent = getAccentColor(accentColorEnum, isDark: false);
    final darkAccent = getAccentColor(accentColorEnum, isDark: true);

    ThemeData lightTheme = MineTheme.lightWithAccent(lightAccent);
    ThemeData darkTheme = MineTheme.darkWithAccent(darkAccent);

    return MaterialApp(
      title: 'Inzx',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: toFlutterThemeMode(themeMode),
      home: const MusicApp(),
      builder: (context, child) {
        // Update system UI
        final brightness = Theme.of(context).brightness;
        SystemChrome.setSystemUIOverlayStyle(
          SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: brightness == Brightness.light
                ? Brightness.dark
                : Brightness.light,
            statusBarBrightness: brightness,
            systemNavigationBarColor: brightness == Brightness.light
                ? MineColors.background
                : MineColors.darkBackground,
            systemNavigationBarIconBrightness: brightness == Brightness.light
                ? Brightness.dark
                : Brightness.light,
          ),
        );

        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(
              MediaQuery.of(context).textScaler.scale(1.0).clamp(0.8, 1.2),
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
